Feature: Writing Options Contracts

    As an investor,
    I want to write an option contract for a pair of ERC20 assets,
    so that I can pursue advanced hedging strategies on Ethereum.

    Background: Token approvals
        Given Alice has approved Engine to spend sufficient WETH
        And Alice has approved Engine to spend sufficient DAI

    Scenario: Write single options lot
        When Alice creates a new option type:
            | underlying asset | underlying amount | exercise asset | exercise amount | exercise time | expiry time |
            | WETH             | 1                 | DAI            | 1600            | 2022-11-01    | 2022-12-01  |
        And Alice writes an options lot:
            | option type | amount |
            | 1           | 7      |
        Then there should be 1 option type:
            | underlying asset | underlying amount | exercise asset | exercise amount | exercise time | expiry time |
            | WETH             | 1                 | DAI            | 1600            | 2022-11-01    | 2022-12-01  |
        And Alice should own an options NFT for option type XYZ
        And Alice should own a claim NFT for option type XYZ:
            | type  | id | amount written | claimed |
            | claim | 1  | 7              | 0       |

    Scenario: Write multiple options lots
        When Alice creates a new option type:
            | underlying asset | underlying amount | exercise asset | exercise amount | exercise time | expiry time |
            | WETH             | 1                 | DAI            | 1600            | 2022-11-01    | 2022-12-01  |
        And Alice writes an options lot:
            | option type | amount |
            | 1           | 7      |
        And Alice writes an options lot:
            | option type | amount |
            | 1           | 3      |
        Then there should be 1 option type:
            | underlying asset | underlying amount | exercise asset | exercise amount | exercise time | expiry time |
            | WETH             | 1                 | DAI            | 1600            | 2022-11-01    | 2022-12-01  |
        And Alice should own an options NFT for option type XYZ
        And Alice should own a claim NFT for option type XYZ:
            | type  | id | amount written | claimed |
            | claim | 1  | 7              | 0       |
        And Alice should own a claim NFT for option type XYZ:
            | type  | id | amount written | claimed |
            | claim | 2  | 3              | 0       |

    Scenario: Write new options lot to existing claim
# TODO



# Write Options (create new type, write options, redeem claims)
# Exercise Options
# Administer Protocol (sweep fees, set fee amount, set fee to)
# Render NFT
