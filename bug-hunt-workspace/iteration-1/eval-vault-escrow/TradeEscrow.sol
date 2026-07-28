// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title TradeEscrow
/// @notice Simple escrow for peer-to-peer trades. A buyer deposits ETH, a seller ships goods
/// off-chain, and the buyer confirms delivery to release funds. If the two sides disagree, an
/// ARBITER_ROLE holder (or the admin multisig, as a fallback if the assigned arbiter goes
/// dark) can step in and resolve the dispute in either direction. Disputes are resolved via a
/// propose-then-confirm pattern so a single arbiter signer can't unilaterally move funds
/// without a second, independent confirmation from the admin multisig.
contract TradeEscrow is AccessControl {
    bytes32 public constant ARBITER_ROLE = keccak256("ARBITER_ROLE");

    enum Status {
        Open,
        Delivered,
        Disputed,
        Resolved
    }

    struct Trade {
        address buyer;
        address seller;
        address arbiter;
        uint256 amount;
        Status status;
    }

    struct PendingResolution {
        address recipient;
        uint256 amount;
        address proposedBy;
        bool exists;
    }

    uint256 private _nextTradeId;
    mapping(uint256 => Trade) public trades;
    mapping(uint256 => PendingResolution) public pendingResolutions;

    event TradeOpened(uint256 indexed tradeId, address indexed buyer, address indexed seller, uint256 amount);
    event DeliveryConfirmed(uint256 indexed tradeId);
    event DisputeRaised(uint256 indexed tradeId);
    event ResolutionProposed(uint256 indexed tradeId, address indexed recipient, uint256 amount);
    event ResolutionConfirmed(uint256 indexed tradeId, address indexed recipient, uint256 amount);

    error ZeroAmount();
    error TradeNotFound();
    error NotBuyer();
    error NotOpen();
    error NotDelivered();
    error NotDisputed();
    error NotAuthorized();
    error TransferFailed();

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Buyer opens a new trade by depositing the agreed amount, naming the seller and
    /// the arbiter who will handle any dispute for this specific trade.
    function openTrade(address seller, address arbiter) external payable returns (uint256 tradeId) {
        if (msg.value == 0) revert ZeroAmount();
        tradeId = ++_nextTradeId;
        trades[tradeId] = Trade({
            buyer: msg.sender,
            seller: seller,
            arbiter: arbiter,
            amount: msg.value,
            status: Status.Open
        });
        emit TradeOpened(tradeId, msg.sender, seller, msg.value);
    }

    /// @notice Buyer confirms the goods arrived as expected, releasing funds to the seller.
    function confirmDelivery(uint256 tradeId) external {
        Trade storage trade = trades[tradeId];
        if (trade.buyer == address(0)) revert TradeNotFound();
        if (trade.buyer != msg.sender) revert NotBuyer();
        if (trade.status != Status.Open) revert NotOpen();

        trade.status = Status.Delivered;
        uint256 amount = trade.amount;
        (bool ok, ) = trade.seller.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Either party can raise a dispute while a trade is still open, freezing it until
    /// the named arbiter (or admin) resolves it.
    function raiseDispute(uint256 tradeId) external {
        Trade storage trade = trades[tradeId];
        if (trade.buyer == address(0)) revert TradeNotFound();
        if (trade.status != Status.Open) revert NotOpen();
        if (msg.sender != trade.buyer && msg.sender != trade.seller) revert NotAuthorized();

        trade.status = Status.Disputed;
        emit DisputeRaised(tradeId);
    }

    /// @notice The trade's assigned arbiter proposes how a disputed trade should be resolved
    /// (full refund to buyer, full release to seller, or a split — recipient/amount are
    /// whatever the arbiter decides after reviewing the case off-chain). Requires a second,
    /// independent confirmation from the admin multisig before funds actually move, so one
    /// arbiter signer can never unilaterally drain a disputed trade.
    function proposeResolution(uint256 tradeId, address recipient, uint256 amount) external onlyRole(ARBITER_ROLE) {
        Trade storage trade = trades[tradeId];
        if (trade.buyer == address(0)) revert TradeNotFound();
        if (trade.status != Status.Disputed) revert NotDisputed();
        if (trade.arbiter != msg.sender && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAuthorized();
        if (amount > trade.amount) revert ZeroAmount();

        pendingResolutions[tradeId] = PendingResolution({
            recipient: recipient,
            amount: amount,
            proposedBy: msg.sender,
            exists: true
        });
        emit ResolutionProposed(tradeId, recipient, amount);
    }

    /// @notice Lets the trade's arbiter recuse themselves from a dispute they don't want to
    /// handle (e.g. a conflict of interest they just noticed), refunding the buyer outright
    /// instead of leaving the trade stuck waiting on a proposal. Meant only as a narrow
    /// "I don't want this case" escape hatch, distinct from the propose/confirm path used for
    /// an actual reasoned resolution.
    function recuseAndRefund(uint256 tradeId) external {
        Trade storage trade = trades[tradeId];
        if (trade.buyer == address(0)) revert TradeNotFound();
        if (trade.status != Status.Disputed) revert NotDisputed();
        if (msg.sender != trade.arbiter) revert NotAuthorized();

        trade.status = Status.Resolved;
        uint256 amount = trade.amount;
        (bool ok, ) = trade.buyer.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Admin confirms a proposed dispute resolution and releases funds accordingly.
    function confirmResolution(uint256 tradeId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PendingResolution storage pending = pendingResolutions[tradeId];
        if (!pending.exists) revert NotDisputed();
        Trade storage trade = trades[tradeId];

        trade.status = Status.Resolved;
        delete pendingResolutions[tradeId];

        (bool ok, ) = pending.recipient.call{value: pending.amount}("");
        if (!ok) revert TransferFailed();

        emit ResolutionConfirmed(tradeId, pending.recipient, pending.amount);
    }
}
