// SPDX-License-Identifier: BUSL 1.1
// Valorem Labs Inc. (c) 2022.
pragma solidity 0.8.16;

import "./utils/BaseEngineTest.sol";
import "./utils/InvariantTest.sol";

import {OptionWriter} from "./actors/OptionWriter.sol";
import {OptionHolder} from "./actors/OptionHolder.sol";
import {ProtocolAdmin} from "./actors/ProtocolAdmin.sol";
import {Timekeeper} from "./actors/Timekeeper.sol";

/// @notice Invariant tests for OptionSettlementEngine
contract OptionSettlementEngineInvariantTest is BaseEngineTest, InvariantTest {
    OptionWriter internal writer;
    OptionHolder internal holder;
    ProtocolAdmin internal admin;
    Timekeeper internal timekeeper;

    uint256[] internal optionTypes;
    uint256[] internal claimsWritten;
    mapping(address => uint256) internal positionBalances;

    function setUp() public override {
        super.setUp();

        holder = new OptionHolder(engine, this);
        writer = new OptionWriter(engine, this, address(holder));
        admin = new ProtocolAdmin(engine, this);
        timekeeper = new Timekeeper();

        targetContract(address(writer));
        targetContract(address(holder));
        targetContract(address(admin));
        targetContract(address(timekeeper));

        excludeContract(address(engine));
        excludeContract(address(generator));

        targetSender(address(0xDEAD));

        _mintTokensForAddress(address(writer));
        _mintTokensForAddress(address(holder));

        console.logString("setUp");
    }

    function invariant_alwaysBlue() public {
        assertTrue(true);
    }

    // balances between the actors and engine should always add up to their original sums
    function invariant_erc20_balances() public {
        console.logString("erc20 balances");
        for (uint256 i = 0; i < ERC20S.length; i++) {
            IERC20 erc20 = ERC20S[i];
            uint256 minted = erc20.balanceOf(address(writer));
            minted += erc20.balanceOf(address(holder));
            minted += erc20.balanceOf(address(admin));
            minted += erc20.balanceOf(address(engine));

            // Not used for invariant tests, but accounting is necessary
            // for accounts minted to when BaseEngineTest.setUp() is called
            minted += erc20.balanceOf(ALICE);
            minted += erc20.balanceOf(BOB);
            minted += erc20.balanceOf(CAROL);

            assertEq(minted, erc20.totalSupply());
        }
    }

    // check erc1155 issuance against claim() method
    function invariant_options_written_match_claims() public {
        for (uint256 i = 0; i < optionTypes.length; i++) {
            // get option type balance from erc1155 impl
            uint256 optionTypeId = optionTypes[i];
            uint256 totalWrittenERC20 = engine.balanceOf(address(holder), optionTypeId);
            totalWrittenERC20 += engine.balanceOf(address(writer), optionTypeId);

            // get option type balance from checking all claims sequentially
            uint256 claimIndex = 1;
            uint256 totalWrittenFromClaims = 0;
            while (true) {
                IOptionSettlementEngine.Claim memory claim = engine.claim(optionTypeId + claimIndex);
                if (claim.amountWritten == 0) {
                    // claim isn't initialized
                    break;
                }
                totalWrittenFromClaims += claim.amountWritten;
            }

            // assert equality
            assertEq(totalWrittenFromClaims, totalWrittenERC20);
        }
    }

    // fee balances and claim positions should sum to the amount stored in the engine, within
    // some amount of wei (due to rounding and fractional assignment)
    function invariant_positions_accounting() public {
        // tally positions for claims
        for (uint256 i = 0; i < claimsWritten.length; i++) {
            uint256 claimId = claimsWritten[i];
            IOptionSettlementEngine.Position memory position = engine.position(claimId);
            positionBalances[position.underlyingAsset] += uint256(position.underlyingAmount);
            positionBalances[position.exerciseAsset] += uint256(position.exerciseAmount);
        }

        // positions plus fee balances should sum to engine balance within some amount of wei
        for (uint256 i = 0; i < ERC20S.length; i++) {
            IERC20 erc20 = ERC20S[i];
            uint256 positionBalance = positionBalances[address(erc20)];
            uint256 feeBalance = engine.feeBalance(address(erc20));
            // balances should be equal within 10 wei; this wei is the dust which accrues on the
            // contract from fractional exercise
            assertApproxEqAbs(erc20.balanceOf(address(engine)), positionBalance + feeBalance, 10);
            positionBalances[address(erc20)] = 0;
        }
    }

    // writers will register the option types they create with this callback
    function addOptionType(uint256 optionId) public {
        optionTypes.push(optionId);
    }

    function getOptionTypes() public view returns (uint256[] memory){
        return optionTypes;
    }

    // writers will register the claim ids they create with this callback
    function addClaimId(uint256 claimId) public {
        claimsWritten.push(claimId);
    }

    function getClaimIds() public view returns (uint256[] memory) {
        return claimsWritten;
    }
}
