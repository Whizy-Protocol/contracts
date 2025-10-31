// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {AaveFork} from "../src/forks/AaveFork.sol";
import {CompoundFork} from "../src/forks/CompoundFork.sol";
import {MorphoFork} from "../src/forks/MorphoFork.sol";

contract UpdateAPYScript is Script {
    // Fork addresses from .env
    address constant AAVE_FORK = 0x6c83bC24a8B6592244442aFc2ba8B7B207aa29Ca;
    address constant MORPHO_FORK = 0x4abA3Ad7A619Da4c0B6Fec764fc2D1816f8EcDe0;
    address constant COMPOUND_FORK = 0x1b5d6a14c867316e0164f38f12C5dC2EB5a13E35;

    // New APY values in basis points (1240 = 12.4%, 620 = 6.2%, 480 = 4.8%)
    uint256 constant AAVE_APY = 1240; // 12.4%
    uint256 constant MORPHO_APY = 620; // 6.2%
    uint256 constant COMPOUND_APY = 480; // 4.8%

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n=== Updating Protocol APY Values ===");
        console.log("Updating with address:", deployer);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Update Aave Fork APY
        console.log("1. Updating Aave Fork APY...");
        console.log("   Address:", AAVE_FORK);
        AaveFork aaveFork = AaveFork(AAVE_FORK);
        uint256 oldAaveApy = aaveFork.getCurrentApy();
        console.log("   Old APY (basis points):", oldAaveApy);
        aaveFork.setCurrentApy(AAVE_APY);
        uint256 newAaveApy = aaveFork.getCurrentApy();
        console.log("   New APY (basis points):", newAaveApy);
        console.log("");

        // Update Morpho Fork APY
        console.log("2. Updating Morpho Fork APY...");
        console.log("   Address:", MORPHO_FORK);
        MorphoFork morphoFork = MorphoFork(MORPHO_FORK);
        uint256 oldMorphoApy = morphoFork.getCurrentApy();
        console.log("   Old APY (basis points):", oldMorphoApy);
        morphoFork.setCurrentApy(MORPHO_APY);
        uint256 newMorphoApy = morphoFork.getCurrentApy();
        console.log("   New APY (basis points):", newMorphoApy);
        console.log("");

        // Update Compound Fork APY
        console.log("3. Updating Compound Fork APY...");
        console.log("   Address:", COMPOUND_FORK);
        CompoundFork compoundFork = CompoundFork(COMPOUND_FORK);
        uint256 oldCompoundApy = compoundFork.getCurrentApy();
        console.log("   Old APY (basis points):", oldCompoundApy);
        compoundFork.setBaseApy(COMPOUND_APY);
        uint256 newCompoundApy = compoundFork.getCurrentApy();
        console.log("   New APY (basis points):", newCompoundApy);
        console.log("");

        vm.stopBroadcast();

        console.log("=== APY Update Summary ===");
        console.log("");
        console.log("Aave:");
        console.log("  - Fork:        ", AAVE_FORK);
        console.log("  - APY:          12.4%");
        console.log("  - Risk Level:   3/10");
        console.log("Morpho:");
        console.log("  - Fork:        ", MORPHO_FORK);
        console.log("  - APY:          6.2%");
        console.log("  - Risk Level:   4/10");
        console.log("Compound:");
        console.log("  - Fork:        ", COMPOUND_FORK);
        console.log("  - APY:          4.8%");
        console.log("  - Risk Level:   2/10");
        console.log("");
        console.log("=== Update Complete ===");
        console.log("");
    }

    function _formatApy(
        uint256 basisPoints
    ) internal pure returns (string memory) {
        uint256 wholePart = basisPoints / 100;
        uint256 decimalPart = basisPoints % 100;

        if (decimalPart == 0) {
            return string(abi.encodePacked(_uint2str(wholePart), ".0"));
        } else if (decimalPart < 10) {
            return
                string(
                    abi.encodePacked(
                        _uint2str(wholePart),
                        ".0",
                        _uint2str(decimalPart)
                    )
                );
        } else {
            return
                string(
                    abi.encodePacked(
                        _uint2str(wholePart),
                        ".",
                        _uint2str(decimalPart)
                    )
                );
        }
    }

    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
