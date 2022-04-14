```
Base64.encode(bytes) (src/Flat.sol#12-71) contains an incorrect shift operation: mstore(uint256,uint256)(resultPtr_encode_asm_0 - 2,0x3d3d << 240) (src/Flat.sol#61)
Base64.encode(bytes) (src/Flat.sol#12-71) contains an incorrect shift operation: mstore(uint256,uint256)(resultPtr_encode_asm_0 - 1,0x3d << 248) (src/Flat.sol#64)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#shift-parameter-mixup

Base64.encode(bytes) (src/Flat.sol#12-71) performs a multiplication on the result of a division:
	-encodedLen = 4 * ((len + 2) / 3) (src/Flat.sol#17)
OptionSettlementEngine.write(uint256,uint112) (src/Flat.sol#1151-1209) performs a multiplication on the result of a division:
	-fee = ((rxAmount / 10000) * feeBps) (src/Flat.sol#1165)
OptionSettlementEngine.exercise(uint256,uint112) (src/Flat.sol#1283-1326) performs a multiplication on the result of a division:
	-fee = ((rxAmount / 10000) * feeBps) (src/Flat.sol#1300)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#divide-before-multiply

OptionSettlementEngine.setFeeTo(address).newFeeTo (src/Flat.sol#1020) lacks a zero-check on :
		- feeTo = newFeeTo (src/Flat.sol#1022)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#missing-zero-address-validation

ERC20.permit(address,address,uint256,uint256,uint8,bytes32,bytes32) (src/Flat.sol#184-228) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(deadline >= block.timestamp,PERMIT_DEADLINE_EXPIRED) (src/Flat.sol#193)
OptionSettlementEngine.newChain(IOptionSettlementEngine.Option) (src/Flat.sol#1083-1149) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(optionInfo.expiryTimestamp >= (block.timestamp + 86400),Expiry < 24 hours from now.) (src/Flat.sol#1098-1101)
OptionSettlementEngine.write(uint256,uint112) (src/Flat.sol#1151-1209) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(optionRecord.expiryTimestamp > block.timestamp,Can't write expired options) (src/Flat.sol#1159-1162)
OptionSettlementEngine.exercise(uint256,uint112) (src/Flat.sol#1283-1326) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(optionRecord.exerciseTimestamp <= block.timestamp,Too early to exercise) (src/Flat.sol#1289-1292)
	- require(bool,string)(optionRecord.expiryTimestamp >= block.timestamp,too late to exercise) (src/Flat.sol#1293-1296)
OptionSettlementEngine.redeem(uint256) (src/Flat.sol#1329-1381) uses timestamp for comparisons
	Dangerous comparisons:
	- require(bool,string)(optionRecord.expiryTimestamp <= block.timestamp,Not expired yet) (src/Flat.sol#1342-1345)
OptionSettlementEngine.underlying(uint256) (src/Flat.sol#1383-1417) uses timestamp for comparisons
	Dangerous comparisons:
	- expired = (optionRecord.expiryTimestamp > block.timestamp) (src/Flat.sol#1392)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#block-timestamp

Base64.encode(bytes) (src/Flat.sol#12-71) uses assembly
	- INLINE ASM (src/Flat.sol#24-68)
SafeTransferLib.safeTransferETH(address,uint256) (src/Flat.sol#849-858) uses assembly
	- INLINE ASM (src/Flat.sol#852-855)
SafeTransferLib.safeTransferFrom(ERC20,address,address,uint256) (src/Flat.sol#864-895) uses assembly
	- INLINE ASM (src/Flat.sol#872-892)
SafeTransferLib.safeTransfer(ERC20,address,uint256) (src/Flat.sol#897-926) uses assembly
	- INLINE ASM (src/Flat.sol#904-923)
SafeTransferLib.safeApprove(ERC20,address,uint256) (src/Flat.sol#928-957) uses assembly
	- INLINE ASM (src/Flat.sol#935-954)
OptionSettlementEngine.vrf() (src/Flat.sol#1054-1064) uses assembly
	- INLINE ASM (src/Flat.sol#1057-1063)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#assembly-usage

ERC1155._batchBurn(address,uint256[],uint256[]) (src/Flat.sol#476-496) is never used and should be removed
ERC1155._mint(address,uint256,uint256,bytes) (src/Flat.sol#426-443) is never used and should be removed
ERC20._burn(address,uint256) (src/Flat.sol#263-273) is never used and should be removed
ERC20._mint(address,uint256) (src/Flat.sol#251-261) is never used and should be removed
SafeTransferLib.safeApprove(ERC20,address,uint256) (src/Flat.sol#928-957) is never used and should be removed
SafeTransferLib.safeTransferETH(address,uint256) (src/Flat.sol#849-858) is never used and should be removed
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#dead-code

Pragma version0.8.11 (src/Flat.sol#2) necessitates a version too recent to be trusted. Consider deploying with 0.6.12/0.7.6/0.8.7
solc-0.8.11 is not recommended for deployment
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#incorrect-versions-of-solidity

Function ERC20.DOMAIN_SEPARATOR() (src/Flat.sol#230-232) is not in mixedCase
Variable ERC20.INITIAL_CHAIN_ID (src/Flat.sol#109) is not in mixedCase
Variable ERC20.INITIAL_DOMAIN_SEPARATOR (src/Flat.sol#111) is not in mixedCase
Variable OptionSettlementEngine._option (src/Flat.sol#999) is not in mixedCase
Variable OptionSettlementEngine._claim (src/Flat.sol#1002) is not in mixedCase
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#conformance-to-solidity-naming-conventions

SafeTransferLib.safeTransferFrom(ERC20,address,address,uint256) (src/Flat.sol#864-895) uses literals with too many digits:
	- mstore(uint256,uint256)(freeMemoryPointer_safeTransferFrom_asm_0,0x23b872dd00000000000000000000000000000000000000000000000000000000) (src/Flat.sol#877)
SafeTransferLib.safeTransfer(ERC20,address,uint256) (src/Flat.sol#897-926) uses literals with too many digits:
	- mstore(uint256,uint256)(freeMemoryPointer_safeTransfer_asm_0,0xa9059cbb00000000000000000000000000000000000000000000000000000000) (src/Flat.sol#909)
SafeTransferLib.safeApprove(ERC20,address,uint256) (src/Flat.sol#928-957) uses literals with too many digits:
	- mstore(uint256,uint256)(freeMemoryPointer_safeApprove_asm_0,0x095ea7b300000000000000000000000000000000000000000000000000000000) (src/Flat.sol#940)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#too-many-digits

approve(address,uint256) should be declared external:
	- ERC20.approve(address,uint256) (src/Flat.sol#136-142)
transfer(address,uint256) should be declared external:
	- ERC20.transfer(address,uint256) (src/Flat.sol#144-156)
transferFrom(address,address,uint256) should be declared external:
	- ERC20.transferFrom(address,address,uint256) (src/Flat.sol#158-178)
permit(address,address,uint256,uint256,uint8,bytes32,bytes32) should be declared external:
	- ERC20.permit(address,address,uint256,uint256,uint8,bytes32,bytes32) (src/Flat.sol#184-228)
uri(uint256) should be declared external:
	- ERC1155.uri(uint256) (src/Flat.sol#313)
	- OptionSettlementEngine.uri(uint256) (src/Flat.sol#1066-1081)
setApprovalForAll(address,bool) should be declared external:
	- ERC1155.setApprovalForAll(address,bool) (src/Flat.sol#319-323)
safeTransferFrom(address,address,uint256,uint256,bytes) should be declared external:
	- ERC1155.safeTransferFrom(address,address,uint256,uint256,bytes) (src/Flat.sol#325-346)
safeBatchTransferFrom(address,address,uint256[],uint256[],bytes) should be declared external:
	- ERC1155.safeBatchTransferFrom(address,address,uint256[],uint256[],bytes) (src/Flat.sol#348-388)
balanceOfBatch(address[],uint256[]) should be declared external:
	- ERC1155.balanceOfBatch(address[],uint256[]) (src/Flat.sol#390-409)
supportsInterface(bytes4) should be declared external:
	- ERC1155.supportsInterface(bytes4) (src/Flat.sol#415-420)
setFeeTo(address) should be declared external:
	- OptionSettlementEngine.setFeeTo(address) (src/Flat.sol#1020-1023)
sweepFees(address[]) should be declared external:
	- OptionSettlementEngine.sweepFees(address[]) (src/Flat.sol#1025-1051)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#public-function-that-could-be-declared-external
