// SPDX-License-Identifier: MIT
//
// DEPLOYMENT NOTE: compile with `viaIR: true` (Remix: Advanced Configurations → "Enable
// optimization" and switch on "Via IR"). registerPlots() has enough local variables that
// standard codegen hits Solidity's "stack too deep" limit; via-IR compiles it fine with no
// behavior change.
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @dev ERC-5192 minimal interface (soulbound token standard).
interface IERC5192 {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);

    function locked(uint256 tokenId) external view returns (bool);
}

/// @title LandCertificate (Onílẹ̀)
/// @notice Core contract of the Onílẹ̀ protocol. Soulbound ERC-721 certificates of land
/// ownership. Certificates cannot be
/// transferred wallet-to-wallet; ownership changes only happen through an issuer-mediated
/// burn-and-reissue (sale, inheritance, or lost-wallet recovery). Each ISSUER_ROLE holder
/// represents one verified issuer (an estate developer or a state Ministry of Lands) and
/// should be a multisig address, not an individual employee's EOA, so no single person can
/// reissue titles. DEFAULT_ADMIN_ROLE (which grants/revokes ISSUER_ROLE) should likewise be
/// held by a multisig. Plot facts and document hashes live directly in contract storage —
/// no off-chain metadata store to keep pinned — and `tokenURI` renders them as an on-chain
/// base64 JSON blob for wallets/explorers.
contract LandCertificate is ERC721, AccessControl, IERC5192 {
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    enum Status {
        Active,
        Reissued,
        Revoked
    }

    enum ReasonCode {
        ORIGINAL,
        SALE,
        INHERITANCE,
        LOST_WALLET
    }

    struct Certificate {
        string plotId;
        uint256 estateId;
        string estateName;
        string surveyPlanNumber;
        string coordinates;
        bytes32 ownerDetailsHash;
        bytes32 documentHash;
        address issuer;
        uint256 issuedAt;
        Status status;
        ReasonCode reason;
        uint256 supersedes;
        uint256 supersededBy;
    }

    /// @dev One registration per land parcel the issuer claims rights to. `titleDocumentHash`
    /// is the hash of the root title document (Certificate of Occupancy, Governor's Consent,
    /// or allocation instrument) the issuer presented as proof of rights — reviewed off-chain
    /// (platform admin, ideally with legal input) before registration, hash kept on-chain as a
    /// tamper-evident record of what was relied on. Not proof of authenticity by itself.
    struct Estate {
        string name;
        bytes32 titleDocumentHash;
        address issuer;
        uint256 registeredAt;
    }

    struct PlotRecord {
        uint256 estateId;
        string surveyPlanNumber;
        string coordinates;
        bool registered;
    }

    /// @dev Staged reissue for LOST_WALLET and beneficiary-less INHERITANCE — the two reason
    /// codes with no independent on-chain check tying the reissue to a specific address. Sits
    /// here until DEFAULT_ADMIN_ROLE confirms it, so a single issuer's own signers can't
    /// unilaterally move a certificate through those paths.
    struct PendingReissue {
        address to;
        bytes32 newOwnerDetailsHash;
        bytes32 newDocumentHash;
        ReasonCode reason;
        address proposedBy;
        bool exists;
    }

    /// @dev Optional per-issuer branding rendered into every certificate's on-chain SVG image.
    /// Purely cosmetic — never read by verifyPlot() or anything else that matters for a
    /// certificate's validity. Stored entirely on-chain (no IPFS/external hosting) so it can
    /// never link-rot; logoSvgPath is length-capped to keep gas costs bounded. brandColorHex
    /// and logoSvgPath are both validated in setIssuerBranding() before being spliced into the
    /// rendered SVG/JSON — see _requireSafeString(), used everywhere an issuer-supplied string
    /// ends up in tokenURI()'s output (this struct's fields, plus estateName/plotId/
    /// surveyPlanNumber/coordinates set via registerEstate/registerPlots).
    struct IssuerBranding {
        string brandColorHex; // exactly 6 hex chars, no leading '#', e.g. "3ddc97"
        string logoSvgPath; // raw SVG <path> "d" attribute data; empty uses a default mark
        bool set;
    }

    uint256 private constant MAX_LOGO_BYTES = 3000;

    uint256 private _nextTokenId;
    uint256 private _nextEstateId;

    mapping(uint256 => Certificate) public certificates;
    mapping(string => uint256) public activeTokenForPlot;
    mapping(uint256 => address) public beneficiaryOf;
    mapping(uint256 => Estate) public estates;
    mapping(string => PlotRecord) public plotRegistry;
    mapping(uint256 => address) public saleApprovedBuyer;
    mapping(uint256 => PendingReissue) public pendingReissues;
    mapping(address => IssuerBranding) public issuerBranding;

    event CertificateIssued(
        uint256 indexed tokenId,
        string plotId,
        address indexed issuer,
        address indexed owner
    );
    event CertificateReissued(uint256 indexed oldTokenId, uint256 indexed newTokenId, ReasonCode reason);
    event CertificateRevoked(uint256 indexed tokenId);
    event BeneficiaryRegistered(uint256 indexed tokenId, address indexed beneficiary);
    event BeneficiaryReassigned(uint256 indexed tokenId, address indexed beneficiary, address indexed by);
    event EstateRegistered(uint256 indexed estateId, string name, address indexed issuer);
    event PlotRegistered(string plotId, uint256 indexed estateId);
    event PlotReassignedByAdmin(string plotId, uint256 indexed estateId, address indexed admin);
    event SaleApproved(uint256 indexed tokenId, address indexed buyer);
    event ReissueProposed(uint256 indexed oldTokenId, address indexed to, ReasonCode reason, address indexed proposedBy);
    event ReissueConfirmed(uint256 indexed oldTokenId, uint256 indexed newTokenId, address indexed confirmedBy);
    event ReissueProposalCancelled(uint256 indexed oldTokenId, address indexed cancelledBy);
    event IssuerBrandingSet(address indexed issuer, string brandColorHex);

    error CertificateNonTransferable();
    error PlotAlreadyActive();
    error CertificateNotActive();
    error NotCertificateOwner();
    error BeneficiaryMismatch();
    error ZeroAddress();
    error NotAuthorizedForCertificate();
    error InvalidReasonCode();
    error InvalidColor();
    error LogoTooLarge();
    error UnsafeCharacter();
    error EstateNotFound();
    error PlotNotRegistered();
    error PlotAlreadySold();
    error ArrayLengthMismatch();
    error PlotOwnedByAnotherIssuer();
    error SaleNotApproved();
    error NoPendingReissue();

    constructor(address admin) ERC721("Land Certificate", "LANDCERT") {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Register an estate once, before any plot in it is sold. `titleDocumentHash` is
    /// the hash of the root title document proving the issuer's rights to this land — the
    /// document itself is reviewed off-chain before this call is made; only its hash is kept
    /// on-chain. Only the registering issuer (or the admin multisig) can register plots
    /// against this estate afterward.
    function registerEstate(string calldata name, bytes32 titleDocumentHash)
        external
        onlyRole(ISSUER_ROLE)
        returns (uint256 estateId)
    {
        _requireSafeString(name);
        estateId = ++_nextEstateId;
        estates[estateId] = Estate({
            name: name,
            titleDocumentHash: titleDocumentHash,
            issuer: msg.sender,
            registeredAt: block.timestamp
        });
        emit EstateRegistered(estateId, name, msg.sender);
    }

    /// @notice Batch-register plot facts for an already-registered estate (e.g. from an
    /// uploaded survey plan), so individual sales only need a plot ID and a buyer wallet.
    /// Plot IDs share a single namespace across every issuer on the contract, so a plot
    /// already registered by a different issuer cannot be overwritten — only the issuer who
    /// registered it (or admin) can re-register it, and only until it's sold. Once a
    /// certificate exists for a plot, its registered facts are frozen entirely.
    /// For very large estates, call this in a few smaller batches rather than one giant
    /// transaction.
    function registerPlots(
        uint256 estateId,
        string[] calldata plotIds,
        string[] calldata surveyPlanNumbers,
        string[] calldata coordinatesList
    ) external onlyRole(ISSUER_ROLE) {
        Estate storage estate = estates[estateId];
        if (estate.issuer == address(0)) revert EstateNotFound();
        if (msg.sender != estate.issuer && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorizedForCertificate();
        }
        if (plotIds.length != surveyPlanNumbers.length || plotIds.length != coordinatesList.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < plotIds.length; i++) {
            string calldata plotId = plotIds[i];
            _requireSafeString(plotId);
            _requireSafeString(surveyPlanNumbers[i]);
            _requireSafeString(coordinatesList[i]);
            if (activeTokenForPlot[plotId] != 0) revert PlotAlreadySold();

            PlotRecord storage existing = plotRegistry[plotId];
            if (existing.registered) {
                address existingIssuer = estates[existing.estateId].issuer;
                if (existingIssuer != msg.sender && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
                    revert PlotOwnedByAnotherIssuer();
                }
            }

            plotRegistry[plotId] = PlotRecord({
                estateId: estateId,
                surveyPlanNumber: surveyPlanNumbers[i],
                coordinates: coordinatesList[i],
                registered: true
            });
            emit PlotRegistered(plotId, estateId);
        }
    }

    /// @notice Admin-only escape hatch: forcibly reassigns an unsold plot's registration to a
    /// given estate. Plot IDs share one namespace across every issuer, so a malicious or
    /// compromised issuer holding ISSUER_ROLE could register a plot ID it has no rights to,
    /// locking the legitimate issuer out of registerPlots() for that string (registerPlots()
    /// only lets the original registering issuer, or admin, overwrite a registration).
    /// This function fixes that without requiring the admin to also hold ISSUER_ROLE — it
    /// only touches plots with no active certificate; a sold plot is untouchable here.
    function adminReassignPlot(
        uint256 estateId,
        string calldata plotId,
        string calldata surveyPlanNumber,
        string calldata coordinates
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _requireSafeString(plotId);
        _requireSafeString(surveyPlanNumber);
        _requireSafeString(coordinates);
        if (activeTokenForPlot[plotId] != 0) revert PlotAlreadySold();

        Estate storage estate = estates[estateId];
        if (estate.issuer == address(0)) revert EstateNotFound();

        plotRegistry[plotId] = PlotRecord({
            estateId: estateId,
            surveyPlanNumber: surveyPlanNumber,
            coordinates: coordinates,
            registered: true
        });
        emit PlotReassignedByAdmin(plotId, estateId, msg.sender);
    }

    /// @notice Issuer sets their own branding — a hex accent color and an optional logo mark —
    /// rendered into every certificate they issue's on-chain SVG image. Purely cosmetic, never
    /// affects verifyPlot() or any other correctness check. Set once, reused across every
    /// certificate from this issuer, rather than paying to store it per-certificate.
    /// brandColorHex must be exactly 6 hex characters (no leading '#'); logoSvgPath is raw SVG
    /// <path> "d" attribute data and may be left empty to fall back to a plain default mark.
    /// Both are spliced unescaped into the rendered SVG/JSON, so both are validated here:
    /// brandColorHex must be pure hex digits, and logoSvgPath goes through the same
    /// _requireSafeString() check as every other issuer-supplied string in this contract.
    function setIssuerBranding(string calldata brandColorHex, string calldata logoSvgPath)
        external
        onlyRole(ISSUER_ROLE)
    {
        bytes calldata colorBytes = bytes(brandColorHex);
        if (colorBytes.length != 6) revert InvalidColor();
        for (uint256 i = 0; i < colorBytes.length; i++) {
            if (!_isHexChar(colorBytes[i])) revert InvalidColor();
        }

        if (bytes(logoSvgPath).length > MAX_LOGO_BYTES) revert LogoTooLarge();
        _requireSafeString(logoSvgPath);

        issuerBranding[msg.sender] = IssuerBranding({
            brandColorHex: brandColorHex,
            logoSvgPath: logoSvgPath,
            set: true
        });
        emit IssuerBrandingSet(msg.sender, brandColorHex);
    }

    /// @dev true for ASCII '0'-'9', 'a'-'f', 'A'-'F'.
    function _isHexChar(bytes1 b) internal pure returns (bool) {
        return (b >= 0x30 && b <= 0x39) || (b >= 0x61 && b <= 0x66) || (b >= 0x41 && b <= 0x46);
    }

    /// @dev Every issuer-supplied string that ends up spliced unescaped into tokenURI()'s
    /// JSON/SVG output goes through this first: estateName, plotId, surveyPlanNumber,
    /// coordinates, and logoSvgPath. Rejects '"' (breaks JSON string values and SVG attribute
    /// values), '<' and '>' (open/close an SVG tag from inside text content), '&' (starts an
    /// XML entity, invalid unescaped in SVG text), and '\' (invalid unescaped in strict JSON).
    /// None of these are legitimate in an estate name, plot ID, survey number, coordinate
    /// string, or SVG path "d" data, so rejecting them outright costs no real input. Only
    /// rejects specific ASCII bytes — multi-byte UTF-8 (e.g. Yoruba diacritics) is untouched.
    function _requireSafeString(string calldata s) internal pure {
        bytes calldata data = bytes(s);
        for (uint256 i = 0; i < data.length; i++) {
            bytes1 b = data[i];
            if (b == "\"" || b == "<" || b == ">" || b == "&" || b == "\\") revert UnsafeCharacter();
        }
    }

    /// @notice Mint a new certificate for a registered plot that has no active certificate.
    /// Plot facts come from the estate/plot registry (set once via registerEstate/registerPlots)
    /// and are copied into the certificate here, then carried forward automatically on every
    /// future reissue, so they can never drift between owners.
    function issue(
        address to,
        string calldata plotId,
        bytes32 ownerDetailsHash,
        bytes32 documentHash
    ) external onlyRole(ISSUER_ROLE) returns (uint256 tokenId) {
        if (to == address(0)) revert ZeroAddress();
        if (activeTokenForPlot[plotId] != 0) revert PlotAlreadyActive();

        PlotRecord storage plot = plotRegistry[plotId];
        if (!plot.registered) revert PlotNotRegistered();

        Estate storage estate = estates[plot.estateId];
        if (msg.sender != estate.issuer && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorizedForCertificate();
        }

        tokenId = ++_nextTokenId;
        certificates[tokenId] = Certificate({
            plotId: plotId,
            estateId: plot.estateId,
            estateName: estate.name,
            surveyPlanNumber: plot.surveyPlanNumber,
            coordinates: plot.coordinates,
            ownerDetailsHash: ownerDetailsHash,
            documentHash: documentHash,
            issuer: msg.sender,
            issuedAt: block.timestamp,
            status: Status.Active,
            reason: ReasonCode.ORIGINAL,
            supersedes: 0,
            supersededBy: 0
        });
        activeTokenForPlot[plotId] = tokenId;

        _safeMint(to, tokenId);
        emit Locked(tokenId);
        emit CertificateIssued(tokenId, plotId, msg.sender, to);
    }

    /// @notice Owner-only pre-authorization of a next-of-kin wallet for the inheritance path.
    /// Does not move the certificate; it only records who the issuer should expect to see
    /// during a probate-backed reissue.
    function registerBeneficiary(uint256 tokenId, address beneficiary) external {
        if (ownerOf(tokenId) != msg.sender) revert NotCertificateOwner();
        beneficiaryOf[tokenId] = beneficiary;
        emit BeneficiaryRegistered(tokenId, beneficiary);
    }

    /// @notice Issuer/admin override for a stale beneficiary registration — e.g. the
    /// registered beneficiary predeceased the owner, or the owner died before correcting it,
    /// leaving nobody able to call registerBeneficiary() (owner-only) to fix it. Requires the
    /// same off-chain verification (updated probate/legal documentation) as any other issuer
    /// action. Only works on an active certificate — once reissued or revoked, there's nothing
    /// left here to correct.
    function reassignBeneficiary(uint256 tokenId, address beneficiary) external {
        Certificate storage cert = certificates[tokenId];
        if (cert.status != Status.Active) revert CertificateNotActive();
        if (msg.sender != cert.issuer && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorizedForCertificate();
        }

        beneficiaryOf[tokenId] = beneficiary;
        emit BeneficiaryReassigned(tokenId, beneficiary, msg.sender);
    }

    /// @notice Current owner consents to selling to a specific buyer. Required before the
    /// issuer can reissue(reason: SALE) for this certificate — without it, an issuer (even a
    /// legitimate one whose signers have gone rogue) could otherwise reissue a "sale" the
    /// actual current owner never agreed to. Does not apply to INHERITANCE or LOST_WALLET,
    /// which by definition happen when the owner cannot sign anything.
    function approveSale(uint256 tokenId, address buyer) external {
        if (ownerOf(tokenId) != msg.sender) revert NotCertificateOwner();
        if (buyer == address(0)) revert ZeroAddress();
        saleApprovedBuyer[tokenId] = buyer;
        emit SaleApproved(tokenId, buyer);
    }

    /// @notice Burn an active certificate and mint its replacement after the issuer has
    /// verified the underlying paperwork off-chain (probate, affidavit + police report, or
    /// deed of assignment — only the document hash goes on-chain, never the document itself).
    /// Plot facts carry over unchanged from the certificate being replaced. Callable only by
    /// the certificate's own issuer of record (or the admin multisig), so one issuer can never
    /// reissue a certificate that belongs to a different issuer's plots. A SALE reissue
    /// additionally requires the current owner's on-chain approveSale() for this exact buyer.
    /// LOST_WALLET and beneficiary-less INHERITANCE have no address tied to any independent
    /// party, so instead of executing immediately they're staged here and require a separate
    /// confirmReissue() from the admin multisig alone — the certificate's own issuer can no
    /// longer move it through those two paths unilaterally. Returns 0 when staged this way;
    /// check for that rather than assuming a new token was minted.
    function reissue(
        uint256 oldTokenId,
        address to,
        bytes32 newOwnerDetailsHash,
        bytes32 newDocumentHash,
        ReasonCode reason
    ) external onlyRole(ISSUER_ROLE) returns (uint256 newTokenId) {
        if (to == address(0)) revert ZeroAddress();
        if (reason == ReasonCode.ORIGINAL) revert InvalidReasonCode();

        Certificate storage old = certificates[oldTokenId];
        if (old.status != Status.Active) revert CertificateNotActive();
        if (msg.sender != old.issuer && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorizedForCertificate();
        }

        address beneficiary = beneficiaryOf[oldTokenId];
        if (reason == ReasonCode.INHERITANCE && beneficiary != address(0) && to != beneficiary) {
            revert BeneficiaryMismatch();
        }
        if (reason == ReasonCode.SALE && saleApprovedBuyer[oldTokenId] != to) {
            revert SaleNotApproved();
        }

        bool requiresAdminConfirmation = reason == ReasonCode.LOST_WALLET
            || (reason == ReasonCode.INHERITANCE && beneficiary == address(0));

        if (requiresAdminConfirmation) {
            pendingReissues[oldTokenId] = PendingReissue({
                to: to,
                newOwnerDetailsHash: newOwnerDetailsHash,
                newDocumentHash: newDocumentHash,
                reason: reason,
                proposedBy: msg.sender,
                exists: true
            });
            emit ReissueProposed(oldTokenId, to, reason, msg.sender);
            return 0;
        }

        newTokenId = _executeReissue(oldTokenId, to, newOwnerDetailsHash, newDocumentHash, reason);
    }

    /// @notice Confirms a staged LOST_WALLET or beneficiary-less INHERITANCE reissue.
    /// Admin-only — deliberately not also open to the certificate's own issuer, since the
    /// whole point is an independent second approver for the two reason codes that have no
    /// other on-chain check tying them to a specific address.
    function confirmReissue(uint256 oldTokenId) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 newTokenId) {
        PendingReissue storage pending = pendingReissues[oldTokenId];
        if (!pending.exists) revert NoPendingReissue();
        if (certificates[oldTokenId].status != Status.Active) revert CertificateNotActive();

        address to = pending.to;
        bytes32 newOwnerDetailsHash = pending.newOwnerDetailsHash;
        bytes32 newDocumentHash = pending.newDocumentHash;
        ReasonCode reason = pending.reason;
        delete pendingReissues[oldTokenId];

        newTokenId = _executeReissue(oldTokenId, to, newOwnerDetailsHash, newDocumentHash, reason);
        emit ReissueConfirmed(oldTokenId, newTokenId, msg.sender);
    }

    /// @notice Withdraws a staged reissue proposal — the proposing issuer changing their
    /// mind, or admin actively rejecting one they find suspicious rather than just leaving it
    /// unconfirmed forever.
    function cancelReissueProposal(uint256 oldTokenId) external {
        if (!pendingReissues[oldTokenId].exists) revert NoPendingReissue();
        Certificate storage old = certificates[oldTokenId];
        if (msg.sender != old.issuer && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorizedForCertificate();
        }
        delete pendingReissues[oldTokenId];
        emit ReissueProposalCancelled(oldTokenId, msg.sender);
    }

    /// @dev Shared burn-and-mint core for both the immediate-execution path in reissue() and
    /// the deferred confirmReissue() path. Preserves the certificate's issuer of record from
    /// the token being replaced rather than crediting whoever happens to call this — otherwise
    /// every admin-confirmed reissue would reattribute the certificate to the admin, locking
    /// the actual issuing organization out of ever touching it again.
    function _executeReissue(
        uint256 oldTokenId,
        address to,
        bytes32 newOwnerDetailsHash,
        bytes32 newDocumentHash,
        ReasonCode reason
    ) internal returns (uint256 newTokenId) {
        Certificate storage old = certificates[oldTokenId];
        address issuerOfRecord = old.issuer;

        old.status = Status.Reissued;
        _burn(oldTokenId);

        newTokenId = ++_nextTokenId;
        certificates[newTokenId] = Certificate({
            plotId: old.plotId,
            estateId: old.estateId,
            estateName: old.estateName,
            surveyPlanNumber: old.surveyPlanNumber,
            coordinates: old.coordinates,
            ownerDetailsHash: newOwnerDetailsHash,
            documentHash: newDocumentHash,
            issuer: issuerOfRecord,
            issuedAt: block.timestamp,
            status: Status.Active,
            reason: reason,
            supersedes: oldTokenId,
            supersededBy: 0
        });
        certificates[oldTokenId].supersededBy = newTokenId;
        activeTokenForPlot[old.plotId] = newTokenId;

        _safeMint(to, newTokenId);
        emit Locked(newTokenId);
        emit CertificateReissued(oldTokenId, newTokenId, reason);
    }

    /// @notice Revoke a certificate without reissuing it (e.g. confirmed fraud). Callable only
    /// by the certificate's own issuer of record (or the admin multisig).
    function revoke(uint256 tokenId) external onlyRole(ISSUER_ROLE) {
        Certificate storage cert = certificates[tokenId];
        if (cert.status != Status.Active) revert CertificateNotActive();
        if (msg.sender != cert.issuer && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorizedForCertificate();
        }

        cert.status = Status.Revoked;
        if (activeTokenForPlot[cert.plotId] == tokenId) {
            delete activeTokenForPlot[cert.plotId];
        }

        _burn(tokenId);
        emit CertificateRevoked(tokenId);
    }

    /// @notice Public, walletless lookup: given a plot ID, returns the active certificate
    /// (if any) and who issued it. Backs the free verification page.
    function verifyPlot(string calldata plotId)
        external
        view
        returns (bool exists, uint256 tokenId, address owner, Certificate memory certificate)
    {
        tokenId = activeTokenForPlot[plotId];
        if (tokenId == 0) {
            return (false, 0, address(0), certificate);
        }

        certificate = certificates[tokenId];
        owner = ownerOf(tokenId);
        exists = true;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _buildTokenURI(tokenId);
    }

    /// @inheritdoc IERC5192
    function locked(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return true;
    }

    // --- On-chain metadata rendering --------------------------------------------------

    function _buildTokenURI(uint256 tokenId) internal view returns (string memory) {
        Certificate storage cert = certificates[tokenId];

        string memory identity = string.concat(
            '{"name":"Land Certificate #', Strings.toString(tokenId),
            '","plotId":"', cert.plotId,
            '","estateId":', Strings.toString(cert.estateId),
            ',"estateName":"', cert.estateName,
            '","surveyPlanNumber":"', cert.surveyPlanNumber,
            '","coordinates":"', cert.coordinates, '"'
        );

        string memory provenance = string.concat(
            ',"status":"', _statusLabel(cert.status),
            '","reason":"', _reasonLabel(cert.reason),
            '","issuer":"', Strings.toHexString(cert.issuer),
            '","issuedAt":', Strings.toString(cert.issuedAt),
            ',"ownerDetailsHash":"', Strings.toHexString(uint256(cert.ownerDetailsHash), 32),
            '","documentHash":"', Strings.toHexString(uint256(cert.documentHash), 32), '"'
        );

        string memory lineage = string.concat(
            ',"supersedes":', Strings.toString(cert.supersedes),
            ',"supersededBy":', Strings.toString(cert.supersededBy)
        );

        string memory image = string.concat(',"image":"', _buildTokenImage(tokenId, cert), '"}');

        string memory json = string.concat(identity, provenance, lineage, image);
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    /// @dev Renders a certificate as an on-chain SVG: issuer's accent color and logo mark (or
    /// a plain default if the issuer hasn't set branding), estate name, plot ID, a status
    /// badge, and a footer with the token ID and reason. Purely cosmetic — see
    /// IssuerBranding's doc comment for the string-escaping caveat.
    function _buildTokenImage(uint256 tokenId, Certificate storage cert) internal view returns (string memory) {
        IssuerBranding storage branding = issuerBranding[cert.issuer];
        string memory accentColor = branding.set ? branding.brandColorHex : "3ddc97";
        string memory statusColor = _statusColor(cert.status);

        string memory top = string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="420" height="260" viewBox="0 0 420 260">',
            '<rect width="420" height="260" fill="#0f1115"/>',
            '<rect width="420" height="8" fill="#', accentColor, '"/>',
            '<text x="24" y="42" font-family="monospace" font-size="10" letter-spacing="3" fill="#9aa1b1">ONILE LAND CERTIFICATE</text>',
            '<text x="24" y="78" font-family="sans-serif" font-size="22" font-weight="700" fill="#e8eaf0">', cert.estateName, '</text>',
            '<text x="24" y="104" font-family="monospace" font-size="14" fill="#9aa1b1">Plot ', cert.plotId, '</text>'
        );

        string memory badge = string.concat(
            '<rect x="24" y="130" width="100" height="24" rx="12" fill="#', statusColor, '" fill-opacity="0.15"/>',
            '<text x="36" y="146" font-family="monospace" font-size="12" font-weight="700" fill="#', statusColor, '">', _statusLabel(cert.status), '</text>'
        );

        string memory footer = string.concat(
            '<text x="24" y="230" font-family="monospace" font-size="10" fill="#5b6270">Token #', Strings.toString(tokenId), ' - ', _reasonLabel(cert.reason), '</text>'
        );

        string memory logo = bytes(branding.logoSvgPath).length > 0
            ? string.concat('<g transform="translate(340,150) scale(0.6)"><path d="', branding.logoSvgPath, '" fill="#', accentColor, '"/></g>')
            : string.concat('<circle cx="376" cy="176" r="20" fill="none" stroke="#', accentColor, '" stroke-width="2"/>');

        string memory svg = string.concat(top, badge, footer, logo, '</svg>');
        return string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(svg)));
    }

    function _statusLabel(Status status) internal pure returns (string memory) {
        if (status == Status.Active) return "ACTIVE";
        if (status == Status.Reissued) return "REISSUED";
        return "REVOKED";
    }

    function _statusColor(Status status) internal pure returns (string memory) {
        if (status == Status.Active) return "3ddc97";
        if (status == Status.Reissued) return "e8b64c";
        return "ff6b6b";
    }

    function _reasonLabel(ReasonCode reason) internal pure returns (string memory) {
        if (reason == ReasonCode.ORIGINAL) return "ORIGINAL";
        if (reason == ReasonCode.SALE) return "SALE";
        if (reason == ReasonCode.INHERITANCE) return "INHERITANCE";
        return "LOST_WALLET";
    }

    // --- Soulbound enforcement -------------------------------------------------------

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert CertificateNonTransferable();
        }
        return super._update(to, tokenId, auth);
    }

    function approve(address, uint256) public pure override {
        revert CertificateNonTransferable();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert CertificateNonTransferable();
    }

    function getApproved(uint256 tokenId) public view override returns (address) {
        _requireOwned(tokenId);
        return address(0);
    }

    function isApprovedForAll(address, address) public pure override returns (bool) {
        return false;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return interfaceId == type(IERC5192).interfaceId || super.supportsInterface(interfaceId);
    }
}
