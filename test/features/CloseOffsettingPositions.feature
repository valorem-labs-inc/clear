Feature: Close Offsetting Positions

    As an Option Writer,
    I want to close offsetting long and short positions on the same instrument,
    so that I can receive collateral back from the clearinghouse.

    # TODO incorporate 1e6 scalar

    Scenario: 1 Option and 1 Claim worth 1 Option

    Scenario: 10 Options and 1 Claim worth 10 Options

    Scenario: 9 Options and 1 Claim worth 10 Options

    Scenario: 11 Options and 1 Claim worth 10 Options

    @Revert
    Scenario: 9 Options and 1 Claim worth 10 Options

    @Revert
    Scenario: 10 Options and 1 Claim worth 9 Options

    @Revert
    Scenario: 1 Option and 1 Claim worth 0 Options

    @Revert
    Scenario: 0 Options and 1 Claim worth 10 Options

    @Revert
    Scenario: 10 Options and 0 Claims
