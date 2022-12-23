// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.16;

import "./BaseActor.sol";

contract OptionWriter is BaseActor {
    address private optionHolder;
    constructor(OptionSettlementEngine _engine, OptionSettlementEngineInvariantTest _test, address _optionHolder) BaseActor(_engine, _test) {
        optionHolder = _optionHolder;
    }

    function newOptionType(uint40 durationToExercise, uint40 durationToExpiry, uint96 underlyingAmount, uint96 exerciseAmount) external {
        console.logString("newOptionType");
        IERC20[] memory mockTokens = test.getMockErc20s();
        uint256 tokenAIndex = _randBetween(uint32(block.timestamp), mockTokens.length);
        uint256 tokenBIndex = _randBetween(uint32(block.timestamp) + 1, mockTokens.length);

        if (tokenBIndex == tokenAIndex) {
            tokenBIndex = ((tokenBIndex + 1) % mockTokens.length);
        }

        if (durationToExpiry <= durationToExercise) {
            durationToExpiry += 1 + durationToExercise - durationToExpiry;
        }

        uint256 optionId = engine.newOptionType(
            address(mockTokens[tokenAIndex]),
            underlyingAmount,
            address(mockTokens[tokenBIndex]),
            exerciseAmount,
            uint40(block.timestamp + durationToExercise),
            uint40(block.timestamp + durationToExpiry) 
        );
        test.addOptionType(optionId);
    }

    function writeNew(uint112 amount) public {
        console.logString("writeNew");
        uint256[] memory optionTypes = test.getOptionTypes();

        if (optionTypes.length == 0){
            console.logString("OptionWriter::WriteNew: no option types created");
            return;
        }

        uint256 optionId = _getRandomElement(uint32(block.timestamp), optionTypes);
        uint256 claimId = engine.write(optionId, amount);
        test.addClaimId(claimId);

        // simulates a 'sale' of the options to the holder from writer
        engine.safeTransferFrom(address(this), optionHolder, optionId, amount, "");
    }

    function writeExisting(uint112 amount) external {
        console.logString("writeExisting");
        uint256[] memory claimsWritten = test.getClaimIds();

        if (claimsWritten.length == 0) {
            writeNew(amount);
            return;
        }

        uint256 claimId = _getRandomElement(uint32(block.timestamp), claimsWritten);
        uint256 optionId = (claimId >> 96) << 96;
        engine.write(claimId, amount);
        // simulates a 'sale' of the options to the holder from writer
        engine.safeTransferFrom(address(this), optionHolder, optionId, amount, "");
    }

    // option writer will opportunistically redeem every claim available
    function redeem() external {
        console.logString("redeem");
        uint256[] memory claimsWritten = test.getClaimIds();
        for (uint256 i = 0; i < claimsWritten.length; i++) {
            uint256 claimId = claimsWritten[i];
            try engine.redeem(claimId) {
                console.logString("successfully redeemed claim");
            } catch {
                // no-op
            }
        }
    }
}
