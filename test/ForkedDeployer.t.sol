// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {ClankerDeployer} from "../src/utils/ClankerDeployer.sol";
import {IClanker} from "../src/interfaces/IClanker.sol";

interface IERC20Min {
    function balanceOf(address) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/// Harness mimicking Clanker.sol's call into the library: an external library call
/// is a DELEGATECALL, so ClankerDeployer.deployToken runs in THIS contract's context
/// (this == the "factory"), and the B20 mint lands here.
contract DeployHarness {
    address public token;
    function run(IClanker.TokenConfig memory cfg, uint256 supply) external returns (address) {
        token = ClankerDeployer.deployToken(cfg, supply);
        return token;
    }
    function pull(address t, address to, uint256 amt) external {
        IERC20Min(t).approve(to, amt); // factory-style approve (then a puller transferFroms)
    }
}

/// LP2c: validates the REAL committed forked ClankerDeployer (not the LP2a mock).
contract ForkedDeployerTest is Test {
    uint256 constant SUPPLY = 100_000_000_000 ether; // Clanker's TOKEN_SUPPLY
    address constant ADMIN = address(0xA11CE);

    function _cfg() internal view returns (IClanker.TokenConfig memory) {
        return IClanker.TokenConfig({
            tokenAdmin: ADMIN,
            name: "Forked Clanker B20",
            symbol: "FCB20",
            salt: bytes32(uint256(0xBEEF)),
            image: "",
            metadata: "",
            context: "",
            originatingChainId: block.chainid // mint fires on this chain
        });
    }

    function test_realDeployer_createsB20_mintsToFactory() public {
        DeployHarness h = new DeployHarness();
        address token = h.run(_cfg(), SUPPLY);

        assertTrue(StdPrecompiles.B20_FACTORY.isB20(token), "real deployer created a B20");
        // mint-to-factory: full supply on the harness (the delegatecall "factory")
        assertEq(IERC20Min(token).balanceOf(address(h)), SUPPLY, "supply on factory");
        assertEq(IERC20Min(token).totalSupply(), SUPPLY, "total supply == TOKEN_SUPPLY");
        assertEq(IERC20Min(token).balanceOf(ADMIN), 0, "admin holds nothing");
        // metadata carried through encodeAssetCreateParams
        assertEq(IERC20Min(token).symbol(), "FCB20", "symbol");
        assertEq(IERC20Min(token).decimals(), 18, "decimals");
    }

    function test_realDeployer_nonOriginatingChain_zeroSupply() public {
        DeployHarness h = new DeployHarness();
        IClanker.TokenConfig memory cfg = _cfg();
        cfg.originatingChainId = block.chainid + 1; // not the originating chain
        address token = h.run(cfg, SUPPLY);
        assertTrue(StdPrecompiles.B20_FACTORY.isB20(token), "B20 still created");
        assertEq(IERC20Min(token).totalSupply(), 0, "zero supply off originating chain");
    }
}
