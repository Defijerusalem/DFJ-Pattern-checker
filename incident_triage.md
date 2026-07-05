# Security Incident Triage

Research pass over 20 incident zip files (`security_incident_100` through `security_incident_119`) supplied for this task. Each row reflects a web search against the exact attack transaction hash(es) and/or attacker address(es) contained in that incident's zip. CONFIRMED means a specific, named primary or reputable secondary source ties the exact hash/address to a named protocol incident. UNCONFIRMED means no such direct match was found, or the only lead was generic/low-reliability (e.g. an address merely labeled "phishing," or an AI-compiled community gist with no primary source behind it).

> **Note on scope:** the task description referenced 290 zip files (asking to process 270), but only 20 zip files (100–119) were actually present in the upload directory. All 20 available files were processed below; no others were found to process.

| Incident ID | Protocol | Date | Loss | Mechanism | Confidence |
|---|---|---|---|---|---|
| security_incident_100 | Palmswap | 2023-07-24 | ~$901K (≈80% later recovered) | Flash-loan price manipulation of the PLP vault: an incorrect USDP↔PLP conversion rate calculation in the PlpManager contract let the vault return more USDT than the attacker deposited. | CONFIRMED |
| security_incident_101 | — | — | — | No direct source match for any of the 4 tx hashes or the attacker address (bsc). | UNCONFIRMED |
| security_incident_102 | — | — | — | No direct source match for the tx hash or attacker address (base). | UNCONFIRMED |
| security_incident_103 | Earning.Farm | 2023-08-09 | ~$528K–$971K (sources vary; some funds frontrun by a MEV bot before the attacker) | Reentrancy in the EFVault `withdraw()` function combined with flawed share-burning logic, repeated across nine transactions. | CONFIRMED |
| security_incident_104 | Zunami Protocol | 2023-08-13/14 | ~$2.1M–$2.18M (≈1,180 ETH) | Flash-loan donation attack that manipulated the `totalHoldings`/`cacheAssetPrice` LP price calculation, inflating SDT/UZD pricing. | CONFIRMED |
| security_incident_105 | Exactly Protocol | 2023-08-18 | ~$7.2M–$12M (reports vary; ~$7.6M across 117 affected accounts) | Reentrancy that bypassed the permit check in the `DebtManager` leverage function using a fake market address, reentering `crossDeleverage` to drain collateral. | CONFIRMED |
| security_incident_106 | — | — | — | No direct source match for the tx hash or attacker address (bsc). | UNCONFIRMED |
| security_incident_107 | — | — | — | Only lead was a low-reliability, AI-compiled GitHub gist loosely associating the address with the Balancer rounding-error incident family; no primary source ties this exact tx/address to a specific Balancer event. | UNCONFIRMED |
| security_incident_108 | — | — | — | No direct source match for the tx hash or attacker address (avalanche). | UNCONFIRMED |
| security_incident_109 | BH Token / PancakeSwap pool | 2023-10-11 | ~$1.27M–$1.575M | Flash-loan manipulation of the BH/USDT pool ratio on PancakeSwap (attacker started with $4.16), allowing over-withdrawal of USDT. | CONFIRMED |
| security_incident_110 | Platypus Finance (3rd 2023 incident) | 2023-10-12 | ~$2.23M total across two EOAs (this address's share ≈$1.65M) | Flash-loan price/slippage-calculation manipulation via smart contracts deployed within the same transaction. | CONFIRMED |
| security_incident_111 | — | — | — | Address (`c0ffeebabe.eth`) is a known whitehat/frontrunner tied to the July 2023 Curve/Vyper reentrancy incident, not a confirmed attacker for this specific transaction — role and event don't match the incident framing. | UNCONFIRMED |
| security_incident_112 | HopeLend | 2023-10-18 | ~$835K | Precision-loss/rounding truncation in the `rayDiv()` function, exploited by donating WBTC to the hEthWBTC lending pool (profit was largely captured by a front-runner, who returned 90% under a bounty deal). | CONFIRMED |
| security_incident_113 | — | — | — | Address only carries a generic "Fake_Phishing" label on Etherscan; no specific incident tied to it. | UNCONFIRMED |
| security_incident_114 | — | — | — | No direct source match for the tx hash or attacker address (ethereum). | UNCONFIRMED |
| security_incident_115 | Onyx Protocol | 2023-11-01 | ~$2.1M (1,164 ETH) | "Empty market" donation attack: attacker inflated the price of a newly listed oPEPE share token by donating PEPE, then borrowed against the overvalued collateral. | CONFIRMED |
| security_incident_116 | — | — | — | No direct source match for the tx hash or attacker address (arbitrum). | UNCONFIRMED |
| security_incident_117 | "RIP MEV Bot 2" (Curve arbitrage bot) | 2023-11 | ~$2M | Missing access control on a public function let the attacker force a third-party MEV bot into unfavorable Curve WBTC/WETH swaps after distorting pool liquidity with a flash loan. | CONFIRMED |
| security_incident_118 | Raft Protocol | 2023-11-10 | ~$6.7M in unbacked R stablecoin minted; ~$1.3M net realized loss (most of the stolen ETH was accidentally burned to a null address due to an uninitialized storage slot) | Precision/index-rate manipulation in the `InterestRatePositionManager` share-minting logic. | CONFIRMED |
| security_incident_119 | — | — | — | No direct source match for the tx hash or attacker address (bsc). | UNCONFIRMED |

## Summary

- **20 of 20** available incident files processed (100–119).
- **10 CONFIRMED**, **10 UNCONFIRMED**.
- The task description mentioned 290 total incident files (asking to process 270), but only these 20 zips were present in the upload directory — the other ~270 were not supplied and could not be processed.
