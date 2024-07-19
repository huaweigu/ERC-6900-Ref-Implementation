// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ModuleEntityLib} from "../../src/helpers/ModuleEntityLib.sol";
import {Call} from "../../src/interfaces/IStandardExecutor.sol";

import {
    RegularResultContract,
    ResultConsumerModule,
    ResultCreatorModule
} from "../mocks/modules/ReturnDataModuleMocks.sol";
import {AccountTestBase} from "../utils/AccountTestBase.sol";
import {TEST_DEFAULT_VALIDATION_ENTITY_ID} from "../utils/TestConstants.sol";

// Tests all the different ways that return data can be read from modules through an account
contract AccountReturnDataTest is AccountTestBase {
    RegularResultContract public regularResultContract;
    ResultCreatorModule public resultCreatorModule;
    ResultConsumerModule public resultConsumerModule;

    function setUp() public {
        _transferOwnershipToTest();

        regularResultContract = new RegularResultContract();
        resultCreatorModule = new ResultCreatorModule();
        resultConsumerModule = new ResultConsumerModule(resultCreatorModule, regularResultContract);

        // Add the result creator module to the account
        bytes32 resultCreatorManifestHash = keccak256(abi.encode(resultCreatorModule.moduleManifest()));
        vm.prank(address(entryPoint));
        account1.installModule({
            module: address(resultCreatorModule),
            manifestHash: resultCreatorManifestHash,
            moduleInstallData: ""
        });
        // Add the result consumer module to the account
        bytes32 resultConsumerManifestHash = keccak256(abi.encode(resultConsumerModule.moduleManifest()));
        vm.prank(address(entryPoint));
        account1.installModule({
            module: address(resultConsumerModule),
            manifestHash: resultConsumerManifestHash,
            moduleInstallData: ""
        });
    }

    // Tests the ability to read the result of module execution functions via the account's fallback
    function test_returnData_fallback() public {
        bytes32 result = ResultCreatorModule(address(account1)).foo();

        assertEq(result, keccak256("bar"));
    }

    // Tests the ability to read the results of contracts called via IStandardExecutor.execute
    function test_returnData_singular_execute() public {
        bytes memory returnData = account1.executeWithAuthorization(
            abi.encodeCall(
                account1.execute,
                (address(regularResultContract), 0, abi.encodeCall(RegularResultContract.foo, ()))
            ),
            _encodeSignature(
                ModuleEntityLib.pack(address(singleSignerValidation), TEST_DEFAULT_VALIDATION_ENTITY_ID),
                GLOBAL_VALIDATION,
                ""
            )
        );

        bytes32 result = abi.decode(abi.decode(returnData, (bytes)), (bytes32));

        assertEq(result, keccak256("bar"));
    }

    // Tests the ability to read the results of multiple contract calls via IStandardExecutor.executeBatch
    function test_returnData_executeBatch() public {
        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: address(regularResultContract),
            value: 0,
            data: abi.encodeCall(RegularResultContract.foo, ())
        });
        calls[1] = Call({
            target: address(regularResultContract),
            value: 0,
            data: abi.encodeCall(RegularResultContract.bar, ())
        });

        bytes memory retData = account1.executeWithAuthorization(
            abi.encodeCall(account1.executeBatch, (calls)),
            _encodeSignature(
                ModuleEntityLib.pack(address(singleSignerValidation), TEST_DEFAULT_VALIDATION_ENTITY_ID),
                GLOBAL_VALIDATION,
                ""
            )
        );

        bytes[] memory returnDatas = abi.decode(retData, (bytes[]));

        bytes32 result1 = abi.decode(returnDatas[0], (bytes32));
        bytes32 result2 = abi.decode(returnDatas[1], (bytes32));

        assertEq(result1, keccak256("bar"));
        assertEq(result2, keccak256("foo"));
    }

    // Tests the ability to read data via routing to fallback functions
    function test_returnData_execFromModule_fallback() public {
        bool result = ResultConsumerModule(address(account1)).checkResultFallback(keccak256("bar"));

        assertTrue(result);
    }

    // Tests the ability to read data via executeWithAuthorization
    function test_returnData_authorized_exec() public {
        bool result = ResultConsumerModule(address(account1)).checkResultExecuteWithAuthorization(
            address(regularResultContract), keccak256("bar")
        );

        assertTrue(result);
    }
}
