# Review of `LandCertificate.sol`

Overall this is a well-organized contract — the soulbound enforcement is clean, the ID-collision-with-zero pitfall is avoided (`_nextTokenId`/`_nextEstateId` pre-increment so `0` stays a safe "none" sentinel), checks-effects-interactions is followed consistently around the `_safeMint` calls, and the NatSpec is unusually thorough about *intent*. That last part is actually what let me find the most interesting bug: the comments describe an authorization model that the code doesn't actually implement in several places.

Below are the issues I found, roughly in order of importance.

## 1. (High) "Admin override" branches are dead code — `onlyRole(ISSUER_ROLE)` blocks admin before the fallback check ever runs

`registerPlots`, `issue`, `reissue`, and `revoke` are all declared:

```solidity
function issue(...) external onlyRole(ISSUER_ROLE) returns (uint256 tokenId) {
    ...
    if (msg.sender != estate.issuer && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
        revert NotAuthorizedForCertificate();
    }
```

The function-level modifier `onlyRole(ISSUER_ROLE)` requires `hasRole(ISSUER_ROLE, msg.sender)` to be true *before the function body even runs*. `DEFAULT_ADMIN_ROLE` does **not** automatically imply `ISSUER_ROLE` in OpenZeppelin's `AccessControl` — it's just the role that can grant/revoke `ISSUER_ROLE`. So if the admin multisig hasn't *also* been separately granted `ISSUER_ROLE`, every call from the admin to `registerPlots`, `issue`, `reissue`, or `revoke` reverts on the modifier with `AccessControlUnauthorizedAccount` — it never reaches the `hasRole(DEFAULT_ADMIN_ROLE, msg.sender)` fallback inside the body. That fallback is unreachable dead code in the normal case.

This directly contradicts the NatSpec, which repeatedly promises an admin escape hatch:
- `registerPlots`: "only the issuer who registered it (**or admin**) can re-register it"
- `revoke`: "Callable only by the certificate's own issuer of record (**or the admin multisig**)"
- `reissue`: same language

It also contradicts the doc comment on `adminReassignPlot` itself, which exists *specifically* because the author recognized this gap for plot registration: "This function fixes that **without requiring the admin to also hold ISSUER_ROLE**." That comment only makes sense if the author assumed the other admin-override checks (in `registerPlots`/`issue`/`reissue`/`revoke`) *don't* need `ISSUER_ROLE` either — but they do, because of the modifier.

**Impact:** In a real incident (compromised or unresponsive issuer, urgent revocation needed), the admin multisig will find it *cannot* directly revoke a certificate, force a reissue, or register/fix plots unless it happens to also hold `ISSUER_ROLE` — something nothing in the docs says is required. This is exactly the kind of gap that gets discovered under pressure, during an actual emergency.

**Fix:** either (a) grant the admin multisig `ISSUER_ROLE` too as a deployment requirement (and document that explicitly), or (b) change these functions to check authorization inside the body only (drop the `onlyRole(ISSUER_ROLE)` modifier and instead require `hasRole(ISSUER_ROLE, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender)` explicitly), matching what `reassignBeneficiary`/`cancelReissueProposal` already do correctly (see below — they have no function-level role modifier).

## 2. (High/Medium) Authorization keyed off a stored address, not live role membership — revoking `ISSUER_ROLE` doesn't fully revoke privileges

`reassignBeneficiary` and `cancelReissueProposal` have **no `onlyRole` modifier at all**. Their entire authorization is:

```solidity
if (msg.sender != cert.issuer && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
    revert NotAuthorizedForCertificate();
}
```

`cert.issuer` is a plain address captured once at issuance time (`issue()`/`_executeReissue()` set `issuer: msg.sender` / `issuerOfRecord`). It is **never re-checked against current role membership**. So if `admin.revokeRole(ISSUER_ROLE, badIssuer)` is called because `badIssuer` was compromised or acting fraudulently, `badIssuer` can *still*, forever after:
- call `reassignBeneficiary(tokenId, attackerAddress)` on any certificate it originally issued, and
- call `cancelReissueProposal(tokenId)` to withdraw a pending `LOST_WALLET`/beneficiary-less `INHERITANCE` proposal that the admin might be in the process of reviewing/rejecting.

`reassignBeneficiary` in particular is concerning: it lets a since-revoked issuer plant a `beneficiaryOf[tokenId]` value that later feeds directly into `reissue()`'s inheritance check (`reason == INHERITANCE && beneficiary != address(0) && to != beneficiary`). Today the blast radius of this is limited because `reissue()` itself *is* correctly gated by `onlyRole(ISSUER_ROLE)` plus a same-issuer-or-admin check, so the revoked issuer can't personally finish the job — but it still means "revoke the role" is not the same as "fully cut this address off," which is a surprising and easy-to-miss property for whoever operates this system. If issue #1 above is ever fixed by granting admin `ISSUER_ROLE`, this gap becomes directly exploitable by a revoked issuer setting up a beneficiary that funnels a subsequent admin-executed reissue toward an address the real owner never approved.

**Fix:** re-check `hasRole(ISSUER_ROLE, msg.sender)` in addition to `msg.sender == cert.issuer` in both functions, so a revoked issuer immediately loses these powers.

## 3. (Medium) `approveSale` consent has no expiry or clean revocation path

```solidity
function approveSale(uint256 tokenId, address buyer) external {
    if (ownerOf(tokenId) != msg.sender) revert NotCertificateOwner();
    if (buyer == address(0)) revert ZeroAddress();
    saleApprovedBuyer[tokenId] = buyer;
    emit SaleApproved(tokenId, buyer);
}
```

Once an owner approves a buyer, that approval sits in storage indefinitely with no timestamp/nonce and no way to explicitly withdraw it (the `ZeroAddress` check means you can't clear it back to "no approval" — the only lever is overwriting it with a *different* address). If the sale falls through off-chain, the owner has no clean way to say "I no longer consent to anything," and the issuer could still process the original approved sale at any later date, possibly well after the deal fell apart, since `reissue()` only checks that `saleApprovedBuyer[oldTokenId] == to`, with no freshness requirement.

**Fix:** consider adding a `revokeSaleApproval(tokenId)` function, or an expiry timestamp checked in `reissue()`.

## 4. (Low) `_requireSafeString` doesn't fully guarantee valid JSON/SVG output

```solidity
function _requireSafeString(string calldata s) internal pure {
    ...
    if (b == "\"" || b == "<" || b == ">" || b == "&" || b == "\\") revert UnsafeCharacter();
}
```

This blocks the characters that would break out of a JSON string or an SVG attribute/tag, which covers the main injection vectors. It does **not** reject raw ASCII control characters (e.g. `0x00`–`0x1F`, including literal newlines/tabs). Strict JSON parsers require control characters inside strings to be escaped (`\n`, `\t`, etc.) — a raw one embedded via `estateName`/`plotId`/`surveyPlanNumber`/`coordinates`/`logoSvgPath` would produce technically-invalid JSON that some wallets/marketplaces could fail to parse, silently breaking `tokenURI()` rendering for that certificate. This is a low-severity availability/robustness issue rather than an exploit (all of these fields are set by trusted `ISSUER_ROLE` holders, not arbitrary users), but worth tightening since it's cheap to fix and the function's whole job is exactly this kind of sanitization.

**Fix:** also reject bytes `< 0x20` (except perhaps none — SVG/JSON have no legitimate use for control chars here).

## 5. (Low / defense-in-depth) No reentrancy guard around `_safeMint`

`issue()` and `_executeReissue()` call `_safeMint`, which invokes `onERC721Received` on contract recipients — an external call. I traced through both call sites and state is fully updated (`activeTokenForPlot`, `certificates`, status flags) *before* the mint call in both cases, so I did not find an exploitable reentrancy path today (e.g., re-entering `issue()` for the same plot during the callback correctly reverts via `activeTokenForPlot[plotId] != 0`). Still, given `to` is attacker-controlled input and the checks-effects-interactions discipline here is currently doing all the work with no structural backstop, I'd suggest adding a `nonReentrant` guard (or at least a comment flagging that CEI must be preserved) as insurance against a future edit accidentally reordering things.

## 6. (Info) Shared plot-ID namespace enables squatting across issuers

The comments already acknowledge this and provide `adminReassignPlot` as the fix, so it's not a new bug — but worth restating for the client: because `plotRegistry`/`activeTokenForPlot` are keyed by a bare `string plotId` shared across *every* issuer, a rogue or careless `ISSUER_ROLE` holder can register a plot ID belonging to another developer's estate before the legitimate issuer does, locking them out until an admin manually intervenes with `adminReassignPlot`. Given `ISSUER_ROLE` is meant to be held by vetted multisigs this is a modest operational risk, but it's the kind of thing that's easy to hit by accident (typo'd plot ID collides with someone else's) and only recoverable via a manual admin transaction.

## 7. (Info) Floating pragma

`pragma solidity ^0.8.24;` — fine for development, but for a production deployment holding legal-title data I'd pin the exact compiler version (and via-IR setting, which the top-of-file comment already flags is required) to remove any ambiguity about what bytecode was actually audited/deployed.

---

### What looked solid
- Soulbound enforcement (`_update` override + `approve`/`setApprovalForAll`/`getApproved` all reverting or returning inert values) is correct and covers all the transfer paths, not just the obvious one.
- The `_nextTokenId`/`_nextEstateId` pre-increment pattern correctly avoids the classic "ID 0 is ambiguous with an unset mapping" bug for `activeTokenForPlot`.
- `confirmReissue`/`cancelReissueProposal` correctly prevent double-execution (proposal is deleted before/after use, `exists` flag checked).
- The `SALE` vs `LOST_WALLET`/beneficiary-less `INHERITANCE` split — requiring independent owner consent for the former and independent admin confirmation for the latter two — is a genuinely good design for the "no on-chain proof ties this to the real party" problem those two reason codes have.
- `tokenURI`/`locked` correctly call `_requireOwned` so burned tokens don't return stale metadata.

The most important fix here is #1 — please double check, before relying on the "admin can act as a backstop" property anywhere in your operational runbook, whether your deployed admin multisig actually also holds `ISSUER_ROLE`. If it doesn't, several of the emergency-response paths described in your own comments don't currently work.
