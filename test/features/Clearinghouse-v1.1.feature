Feature: Net Offsetting Positions

    As an Option Writer,
    I want to net offsetting long and short positions on the same instrument which I hold,
    so that I can receive the underlying asset collateral back from the clearinghouse.

    # TODO incorporate 1e6 scalar for contract units

    Scenario: 1 Option and 1 Claim worth 1 unassigned Option

    Scenario: 10 Options and 1 Claim worth 10 unassigned Options

    Scenario: 9 Options and 1 Claim worth 10 unassigned Options

    Scenario: 11 Options and 1 Claim worth 10 unassigned Options

    @Revert
    Scenario: 9 Options and 1 Claim worth 10 unassigned Options

    @Revert
    Scenario: 10 Options and 1 Claim worth 9 unassigned Options

    @Revert
    Scenario: 1 Option and 1 Claim worth 0 unassigned Options

    @Revert
    Scenario: 0 Options and 1 Claim worth 10 unassigned Options

    @Revert
    Scenario: 10 Options and 0 Claims

Feature: Early Redeem of Fully Assigned Claims

    As an Option Writer,
    I want to redeem a fully assigned Claim which I hold before the expiry timestamp,
    so that I can receive the exercise asset collateral back from the clearinghouse.

    Scenario: 1 Fully Assigned Claim before expiry

    @Revert
    Scenario: 1 Partially Assigned Claim before expiry

    @Revert
    Scenario: 1 Unassigned Claim before expiry
