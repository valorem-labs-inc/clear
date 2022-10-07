// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.11;

import "base64/Base64.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/tokens/ERC1155.sol";
import "./interfaces/IOptionSettlementEngine.sol";
import "solmate/utils/SafeTransferLib.sol";
import "./TokenURIGenerator.sol";

/**
 * Valorem Options V1 is a DeFi money lego enabling writing covered call and covered put, physically settled, options.
 * All written options are fully collateralized against an ERC-20 underlying asset and exercised with an
 * ERC-20 exercise asset using a pseudorandom number per unique option type for fair settlement. Options contracts
 * are issued as fungible ERC-1155 tokens, with each token representing a contract. Option writers are additionally issued
 * an ERC-1155 NFT representing a lot of contracts written for claiming collateral and exercise assignment. This design
 * eliminates the need for market price oracles, and allows for permission-less writing, and gas efficient transfer, of
 * a broad swath of traditional options.
 */

// TODO(DRY code during testing)
// TODO(Gas Optimize)

// @notice This settlement protocol does not support rebase tokens, or fee on transfer tokens

contract OptionSettlementEngine is ERC1155, IOptionSettlementEngine {
    // The protocol fee
    uint8 public immutable feeBps = 5;

    // The address fees accrue to
    address public feeTo = 0x36273803306a3C22bc848f8Db761e974697ece0d;

    // The token type for a given tokenId
    mapping(uint256 => Type) public tokenType;

    // Fee balance for a given token
    mapping(address => uint256) public feeBalance;

    // Input hash to get option token ID if it exists
    mapping(bytes32 => uint256) public hashToOptionToken;

    // The next token id
    uint256 internal nextTokenId = 1;

    // The list of claims for an option
    mapping(uint256 => uint256[]) internal unexercisedClaimsByOption;

    // Accessor for Option contract details
    mapping(uint256 => Option) internal _option;

    // Accessor for claim ticket details
    mapping(uint256 => Claim) internal _claim;

    /// @inheritdoc IOptionSettlementEngine
    function option(uint256 tokenId) external view returns (Option memory optionInfo) {
        optionInfo = _option[tokenId];
    }

    /// @inheritdoc IOptionSettlementEngine
    function claim(uint256 tokenId) external view returns (Claim memory claimInfo) {
        claimInfo = _claim[tokenId];
    }

    /// @inheritdoc IOptionSettlementEngine
    function setFeeTo(address newFeeTo) public {
        if (msg.sender != feeTo) {
            revert AccessControlViolation(msg.sender, feeTo);
        }
        feeTo = newFeeTo;
    }

    /// @inheritdoc IOptionSettlementEngine
    function sweepFees(address[] memory tokens) public {
        address sendFeeTo = feeTo;
        address token;
        uint256 fee;
        uint256 sweep;
        uint256 numTokens = tokens.length;

        unchecked {
            for (uint256 i = 0; i < numTokens; i++) {
                // Get the token and balance to sweep
                token = tokens[i];

                fee = feeBalance[token];
                // Leave 1 wei here as a gas optimization
                if (fee > 1) {
                    sweep = feeBalance[token] - 1;
                    SafeTransferLib.safeTransfer(ERC20(token), sendFeeTo, sweep);
                    feeBalance[token] = 1;
                    emit FeeSwept(token, sendFeeTo, sweep);
                }
            }
        }
    }

    function uri(uint256 tokenId) public view virtual override returns (string memory) {
        Type _type = tokenType[tokenId];
        Option memory optionInfo;

        if (_type == Type.None) {
            revert TokenNotFound(tokenId);
        } else if (_type == Type.Claim) {
            Claim memory claimInfo = _claim[tokenId];

            optionInfo = _option[claimInfo.option];
        } else {
            optionInfo = _option[tokenId];
        }

        TokenURIGenerator.TokenURIParams memory params = TokenURIGenerator.TokenURIParams({
            underlyingAsset: optionInfo.underlyingAsset,
            underlyingSymbol: ERC20(optionInfo.underlyingAsset).symbol(),
            exerciseAsset: optionInfo.exerciseAsset,
            exerciseSymbol: ERC20(optionInfo.exerciseAsset).symbol(),
            exerciseTimestamp: optionInfo.exerciseTimestamp,
            expiryTimestamp: optionInfo.expiryTimestamp,
            underlyingAmount: optionInfo.underlyingAmount,
            exerciseAmount: optionInfo.exerciseAmount,
            tokenType: _type
        });

        return TokenURIGenerator.constructTokenURI(params);
    }

    /// @inheritdoc IOptionSettlementEngine
    function newChain(Option memory optionInfo) external returns (uint256 optionId) {
        // Ensure settlement seed is 0
        optionInfo.settlementSeed = 0;

        // Check that a duplicate chain doesn't exist
        bytes32 chainKey = keccak256(abi.encode(optionInfo));

        // If it does, revert
        if (hashToOptionToken[chainKey] != 0) {
            revert OptionsChainExists(chainKey);
        }

        // Make sure that expiry is at least 24 hours from now
        if (optionInfo.expiryTimestamp < (block.timestamp + 86400)) {
            revert ExpiryTooSoon();
        }

        // Ensure the exercise window is at least 24 hours
        if (optionInfo.expiryTimestamp < (optionInfo.exerciseTimestamp + 86400)) {
            revert ExerciseWindowTooShort();
        }

        // The exercise and underlying assets can't be the same
        if (optionInfo.exerciseAsset == optionInfo.underlyingAsset) {
            revert InvalidAssets(optionInfo.exerciseAsset, optionInfo.underlyingAsset);
        }

        // Use the chainKey to seed entropy
        optionInfo.settlementSeed = uint160(uint256(chainKey));

        // Create option token and increment
        tokenType[nextTokenId] = Type.Option;

        // TODO(Is this check really needed?)
        // Check that both tokens are ERC20 by instantiating them and checking supply
        ERC20 underlyingToken = ERC20(optionInfo.underlyingAsset);
        ERC20 exerciseToken = ERC20(optionInfo.exerciseAsset);

        // Check total supplies and ensure the option will be exercisable
        if (
            underlyingToken.totalSupply() < optionInfo.underlyingAmount
                || exerciseToken.totalSupply() < optionInfo.exerciseAmount
        ) {
            revert InvalidAssets(optionInfo.underlyingAsset, optionInfo.exerciseAsset);
        }

        _option[nextTokenId] = optionInfo;

        optionId = nextTokenId;

        // Increment the next token id to be used
        ++nextTokenId;
        hashToOptionToken[chainKey] = optionId;

        emit NewChain(
            optionId,
            optionInfo.exerciseAsset,
            optionInfo.underlyingAsset,
            optionInfo.exerciseAmount,
            optionInfo.underlyingAmount,
            optionInfo.exerciseTimestamp,
            optionInfo.expiryTimestamp
            );
    }

    /// @inheritdoc IOptionSettlementEngine
    function write(uint256 optionId, uint112 amount) external returns (uint256 claimId) {
        if (tokenType[optionId] != Type.Option) {
            revert InvalidOption(optionId);
        }

        Option storage optionRecord = _option[optionId];

        if (optionRecord.expiryTimestamp <= block.timestamp) {
            revert ExpiredOption(optionId, optionRecord.expiryTimestamp);
        }

        uint256 rxAmount = amount * optionRecord.underlyingAmount;
        uint256 fee = ((rxAmount / 10000) * feeBps);
        address underlyingAsset = optionRecord.underlyingAsset;

        // Transfer the requisite underlying asset
        SafeTransferLib.safeTransferFrom(ERC20(underlyingAsset), msg.sender, address(this), (rxAmount + fee));

        claimId = nextTokenId;

        // Mint the options contracts and claim token
        uint256[] memory tokens = new uint256[](2);
        tokens[0] = optionId;
        tokens[1] = claimId;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = uint256(amount);
        amounts[1] = 1;

        bytes memory data = new bytes(0);

        // Store info about the claim
        tokenType[claimId] = Type.Claim;
        _claim[claimId] = Claim({option: optionId, amountWritten: amount, amountExercised: 0, claimed: false});
        unexercisedClaimsByOption[optionId].push(claimId);

        feeBalance[underlyingAsset] += fee;

        // Increment the next token ID
        ++nextTokenId;

        emit FeeAccrued(underlyingAsset, msg.sender, fee);
        emit OptionsWritten(optionId, msg.sender, claimId, amount);

        // Send tokens to writer
        _batchMint(msg.sender, tokens, amounts, data);
    }

    function assignExercise(uint256 optionId, uint112 amount, uint160 settlementSeed) internal {
        // Number of claims enqueued for this option
        uint256 claimsLen = unexercisedClaimsByOption[optionId].length;

        if (claimsLen == 0) {
            revert NoClaims();
        }

        // Initial storage pointer
        Claim storage claimRecord;

        // Counter for randomness
        uint256 i;

        // To keep track of the slot to overwrite
        uint256 overwrite;

        // Last index in the claims list
        uint256 lastIndex;

        // The new length for the claims list
        uint256 newLen;

        // While there are still options to exercise
        while (amount > 0) {
            // Get the claim number to assign
            uint256 claimNum;
            if (claimsLen == 1) {
                lastIndex = 0;
                claimNum = unexercisedClaimsByOption[optionId][lastIndex];
            } else {
                lastIndex = settlementSeed % claimsLen;
                claimNum = unexercisedClaimsByOption[optionId][lastIndex];
            }

            claimRecord = _claim[claimNum];

            uint112 amountAvailiable = claimRecord.amountWritten - claimRecord.amountExercised;
            uint112 amountPresentlyExercised;
            if (amountAvailiable < amount) {
                amount -= amountAvailiable;
                amountPresentlyExercised = amountAvailiable;
                // We pop the end off and overwrite the old slot

                newLen = claimsLen - 1;
                unexercisedClaimsByOption[optionId].pop();
                if (newLen > 0) {
                    overwrite = unexercisedClaimsByOption[optionId][newLen];
                    // Would be nice if I could pop onto the stack here
                    claimsLen = newLen;
                    unexercisedClaimsByOption[optionId][lastIndex] = overwrite;
                }
            } else {
                amountPresentlyExercised = amount;
                amount = 0;
            }

            claimRecord.amountExercised += amountPresentlyExercised;
            emit ExerciseAssigned(claimNum, optionId, amountPresentlyExercised);

            // Increment for the next loop
            settlementSeed = uint160(uint256(keccak256(abi.encode(settlementSeed, i))));
            i++;
        }

        // Update the settlement seed in storage for the next exercise.
        _option[optionId].settlementSeed = settlementSeed;
    }

    /// @inheritdoc IOptionSettlementEngine
    function exercise(uint256 optionId, uint112 amount) external {
        if (tokenType[optionId] != Type.Option) {
            revert InvalidOption(optionId);
        }

        Option storage optionRecord = _option[optionId];

        if (optionRecord.expiryTimestamp <= block.timestamp) {
            revert ExpiredOption(optionId, optionRecord.expiryTimestamp);
        }
        // Require that we have reached the exercise timestamp
        if (optionRecord.exerciseTimestamp >= block.timestamp) {
            revert ExerciseTooEarly();
        }

        uint256 rxAmount = optionRecord.exerciseAmount * amount;
        uint256 txAmount = optionRecord.underlyingAmount * amount;
        uint256 fee = ((rxAmount / 10000) * feeBps);
        address exerciseAsset = optionRecord.exerciseAsset;

        // Transfer in the requisite exercise asset
        SafeTransferLib.safeTransferFrom(ERC20(exerciseAsset), msg.sender, address(this), (rxAmount + fee));

        // Transfer out the underlying
        SafeTransferLib.safeTransfer(ERC20(optionRecord.underlyingAsset), msg.sender, txAmount);

        assignExercise(optionId, amount, optionRecord.settlementSeed);

        feeBalance[exerciseAsset] += fee;

        _burn(msg.sender, optionId, amount);

        emit FeeAccrued(exerciseAsset, msg.sender, fee);
        emit OptionsExercised(optionId, msg.sender, amount);
    }

    /// @inheritdoc IOptionSettlementEngine
    function redeem(uint256 claimId) external {
        if (tokenType[claimId] != Type.Claim) {
            revert InvalidClaim(claimId);
        }

        uint256 balance = this.balanceOf(msg.sender, claimId);

        if (balance != 1) {
            revert BalanceTooLow();
        }

        Claim storage claimRecord = _claim[claimId];

        if (claimRecord.claimed) {
            revert AlreadyClaimed();
        }

        uint256 optionId = claimRecord.option;
        Option storage optionRecord = _option[optionId];

        if (optionRecord.expiryTimestamp > block.timestamp) {
            revert ClaimTooSoon();
        }

        uint256 exerciseAmount = optionRecord.exerciseAmount * claimRecord.amountExercised;
        uint256 underlyingAmount =
            (optionRecord.underlyingAmount * (claimRecord.amountWritten - claimRecord.amountExercised));

        if (exerciseAmount > 0) {
            SafeTransferLib.safeTransfer(ERC20(optionRecord.exerciseAsset), msg.sender, exerciseAmount);
        }

        if (underlyingAmount > 0) {
            SafeTransferLib.safeTransfer(ERC20(optionRecord.underlyingAsset), msg.sender, underlyingAmount);
        }

        claimRecord.claimed = true;

        _burn(msg.sender, claimId, 1);

        emit ClaimRedeemed(
            claimId,
            optionId,
            msg.sender,
            optionRecord.exerciseAsset,
            optionRecord.underlyingAsset,
            uint96(exerciseAmount),
            uint96(underlyingAmount)
            );
    }

    /// @inheritdoc IOptionSettlementEngine
    function underlying(uint256 tokenId) external view returns (Underlying memory underlyingPositions) {
        if (tokenType[tokenId] == Type.None) {
            revert TokenNotFound(tokenId);
        } else if (tokenType[tokenId] == Type.Option) {
            Option storage optionRecord = _option[tokenId];
            bool expired = (optionRecord.expiryTimestamp > block.timestamp);
            underlyingPositions = Underlying({
                underlyingAsset: optionRecord.underlyingAsset,
                underlyingPosition: expired ? int256(0) : int256(uint256(optionRecord.underlyingAmount)),
                exerciseAsset: optionRecord.exerciseAsset,
                exercisePosition: expired ? int256(0) : -int256(uint256(optionRecord.exerciseAmount))
            });
        } else {
            Claim storage claimRecord = _claim[tokenId];
            Option storage optionRecord = _option[claimRecord.option];
            uint256 exerciseAmount = optionRecord.exerciseAmount * claimRecord.amountExercised;
            uint256 underlyingAmount =
                (optionRecord.underlyingAmount * (claimRecord.amountWritten - claimRecord.amountExercised));
            underlyingPositions = Underlying({
                underlyingAsset: optionRecord.underlyingAsset,
                underlyingPosition: int256(exerciseAmount),
                exerciseAsset: optionRecord.exerciseAsset,
                exercisePosition: int256(underlyingAmount)
            });
        }
    }
}
