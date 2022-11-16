Feature: Write Options

    As an Option Writer,
    I want to write options for a pair of ERC20 assets,
    so that I can pursue advanced trading strategies on Ethereum.

    Background: Token balances, token approvals, and option type creation
        Given Alice has 10_000 DAI and 10 WETH
        And Bob has 10_000 DAI and 10 WETH
        And Carol has 10_000 DAI and 10 WETH
        Given Alice has approved Engine to spend sufficient WETH
        And Alice has approved Engine to spend sufficient DAI
        And Alice creates new option type WETHDAI221201C:
            | underlying asset | underlying amount | exercise asset | exercise amount | earliest exercise | expiry     |
            | WETH             | 1                 | DAI            | 1_300           | 2022-11-01        | 2022-12-01 |

    Scenario: Write options
        When Alice writes an options lot:
            | option type    | amount |
            | WETHDAI221201C | 7      |
        Then there should be 1 option type:
            | underlying asset | underlying amount | exercise asset | exercise amount | earliest exercise | expiry     |
            | WETH             | 1                 | DAI            | 1_300           | 2022-11-01        | 2022-12-01 |
        And Alice should own 7 Option tokens for option type WETHDAI221201C
        And Alice should own 1 Claim NFT for option type WETHDAI221201C
        And Alice should have 10_000 DAI and 9 WETH

    Scenario: Write multiple options to same lot
        When Alice writes an options lot:
            | option type    | amount |
            | WETHDAI221201C | 1      |
        And Alice writes additional options to existing lot:
            | option type    | claim num | amount |
            | WETHDAI221201C | 1         | 3      |
        Then Alice should own 4 Option tokens for option type WETHDAI221201C
        And Alice should own 1 Claim NFT for option type WETHDAI221201C

    Scenario: Sell options
        Given Alice writes an options lot:
            | option type    | amount |
            | WETHDAI221201C | 4      |
        When Alice transfers 1 Option token for option type WETHDAI221201C to Bob
        And Alice transfers 2 Option tokens for option type WETHDAI221201C to Carol
        Then Alice should own 1 Option token for option type WETHDAI221201C
        And Alice should own 1 Claim NFT for option type WETHDAI221201C
        And Bob should own 1 Option token for option type WETHDAI221201C
        And Carol should own 2 Option tokens for option type WETHDAI221201C

    Scenario: Redeem option lot claim, when fully exericised
        Given Alice writes an options lot:
            | option type    | amount |
            | WETHDAI221201C | 7      |
        And Alice sells 7 Option tokens to Bob
        And the time is before expiry
        And Bob exercises 7 Option tokens
        And the time is at expiry
        When Alice redeems their Claim NFT
        Then Alice should own 0 Option tokens for option type WETHDAI221201C
        And Alice should own 0 Claim NFTs for option type WETHDAI221201C
        And Bob should own 0 Option tokens for option type WETHDAI221201C
        And Alice should have 18_100 DAI and 3 WETH
        And Bob should have 900 DAI and 17 WETH

    Scenario: Redeem option lot claim, when partially exericised
        Given Alice writes an options lot:
            | option type    | amount |
            | WETHDAI221201C | 7      |
        And Alice sells 7 Option tokens to Bob
        And the time is before expiry
        And Bob exercises 2 Option tokens
        And the time is at expiry
        When Alice redeems their Claim NFT
        Then Alice should own 0 Option tokens for option type WETHDAI221201C
        And Alice should own 0 Claim NFTs for option type WETHDAI221201C
        And Bob should own 5 Option tokens for option type WETHDAI221201C
        And Alice should have 12_600 DAI and 8 WETH
        And Bob should have 7_400 DAI and 12 WETH

    Scenario: Redeem option lot claim, when expired without exercising
        Given Alice writes an options lot:
            | option type    | amount |
            | WETHDAI221201C | 7      |
        And Alice sells 7 Option tokens to Bob
        And the time is at expiry
        When Alice redeems their Claim NFT
        Then Alice should own 0 Option tokens for option type WETHDAI221201C
        And Alice should own 0 Claim NFTs for option type WETHDAI221201C
        And Bob should own 7 Option tokens for option type WETHDAI221201C
        And Alice should have 10_000 DAI and 10 WETH
        And Bob should have 10_000 DAI and 10 WETH
