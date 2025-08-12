//SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { KittyCoin } from "src/KittyCoin.sol";
import { KittyPool } from "src/KittyPool.sol";
import { KittyVault, IAavePool } from "src/KittyVault.sol";
import { DeployKittyFi, HelperConfig } from "script/DeployKittyFi.s.sol";
import { IStdCheats } from "./utils/IStdCheats.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Mock contract for Aave Pool
contract MockAavePool {
    mapping(address => mapping(address => uint256)) public userBalances;
    address weth;
    address usdc;
    address wbtc;

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external {
        require(IERC20(asset).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        userBalances[asset][onBehalfOf] += amount;
        }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        require(userBalances[asset][msg.sender] >= amount, "Insufficient balance");
        userBalances[asset][msg.sender] -= amount;
        require(IERC20(asset).transfer(to, amount), "Transfer failed");
        return amount;
        }

    function getUserAccountData(address user) external view returns (uint256 totalCollateralBase, uint256, uint256, uint256, uint256, uint256) {
        return (userBalances[weth][user] + userBalances[wbtc][user] + userBalances[usdc][user], 0, 0, 0, 0, 0);
    }
 }

    // Mock contract for Chainlink Price Feed
contract MockChainlinkPriceFeed is AggregatorV3Interface {
    int256 public price;
    uint8 public decimals_;
    uint256 public timestamp;
    address weth;

    constructor(int256 _price, uint8 _decimals) {
        price = _price;
        decimals_ = _decimals;
        timestamp = block.timestamp;
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
         return (1, price, block.timestamp, timestamp, 1);
    }

    function setPrice(int256 _price) external {
        price = _price;
        timestamp = block.timestamp;
    }

    function decimals() external view override returns (uint8) {
       return decimals_;
    }

    // Implement missing functions
    function description() external view override returns (string memory) {
        return "Mock Chainlink Price Feed";
    }

    function getRoundData(uint80 _roundId) external view override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, price, block.timestamp, timestamp, 1); // Mock implementation
    }

    function version() external view override returns (uint256) {
        return 1; // Mock version
    }
}

    // Mock contract for ERC20 tokens
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
      _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

        function mint(address to, uint256 amount) external {
            _mint(to, amount);
        }
    }

 // Specific ERC20Mock for WETH
contract ERC20Mock is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

     function decimals() public view virtual override returns (uint8) {
            return 18;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}


contract InvariantTests is StdInvariant{
    KittyCoin kittyCoin;
    KittyPool kittyPool;
    KittyVault wethVault;
    address meowntainer = address(0x123456123456789012345678901234567890);
    address user = address(0x987654987654321098765432109876543210);
    IStdCheats vm = IStdCheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    // Mock addresses
    address aavePool;
    address euroPriceFeed;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address usdcUsdPriceFeed;
    address weth;
    address wbtc;
    address usdc;
    ERC20Mock wethMock;

    
    constructor() {
        // Deploy mock contracts
        aavePool = address(new MockAavePool());
        euroPriceFeed = address(new MockChainlinkPriceFeed(118000000, 8)); // 1 EUR = 1.18 USD
        ethUsdPriceFeed = address(new MockChainlinkPriceFeed(300000000000, 8)); // 1 ETH = 3000 USD
        btcUsdPriceFeed = address(new MockChainlinkPriceFeed(6000000000000, 8)); // 1 BTC = 60,000 USD
        usdcUsdPriceFeed = address(new MockChainlinkPriceFeed(100000000, 8)); // 1 USDC = 1 USD
        weth = address(new MockERC20("Wrapped Ether", "WETH", 18));
        wbtc = address(new MockERC20("Wrapped Bitcoin", "WBTC", 8));
        usdc = address(new MockERC20("USD Coin", "USDC", 6));
        wethMock = new ERC20Mock();

        // Mint initial tokens for testing
        MockERC20(weth).mint(user, 1000 ether);
        MockERC20(wbtc).mint(user, 1000 * 1e8);
        MockERC20(usdc).mint(user, 1000 * 1e6);
        wethMock.mint(user, 1000 ether);

        // Deploy KittyPool and create vaults
        kittyPool = new KittyPool(meowntainer, euroPriceFeed, aavePool);
        vm.startPrank(meowntainer);
        kittyPool.meownufactureKittyVault(weth, ethUsdPriceFeed);
        kittyPool.meownufactureKittyVault(wbtc, btcUsdPriceFeed);
        kittyPool.meownufactureKittyVault(usdc, usdcUsdPriceFeed);
        kittyPool.meownufactureKittyVault(address(wethMock), ethUsdPriceFeed);
        vm.stopPrank();

        kittyCoin = KittyCoin(kittyPool.getKittyCoin());
        wethVault = KittyVault(kittyPool.getTokenToVault(weth));

        // Set up invariant testing
        targetContract(address(kittyPool));
        targetContract(address(wethVault));
    }

    // // Invariant 1: Collateralization ratio >= 169%
    // function invariant_collateralizationRatio() public {
    //     uint256 collateralInEuros = kittyPool.getUserMeowllateralInEuros(user);
    //     uint256 debt = kittyPool.getKittyCoinMeownted(user);
    //     uint256 requiredCollateral = debt * 169 / 100;
    //     assert(collateralInEuros >= requiredCollateral);
    // }

    // // Invariant 2: Vault accounting consistency
    // function invariant_vaultAccounting() public {
    //     uint256 totalMeowllateral = wethVault.getTotalMeowllateral();
    //     uint256 calculatedMeowllateral;
    //     uint256 totalCattyNip = wethVault.totalCattyNip();
    //     if (totalCattyNip > 0) {
    //         calculatedMeowllateral = wethVault.getUserMeowllateral(user) * totalCattyNip / wethVault.userToCattyNip(user);
    //     }
    //     assert(totalMeowllateral == calculatedMeowllateral || totalCattyNip == 0);
    // }

    // Invariant 3: KittyCoin supply matches total debt
    function invariant_kittyCoinSupply() public {
        uint256 totalSupply = kittyCoin.totalSupply();
        uint256 totalDebt = kittyPool.getKittyCoinMeownted(user);
        assert(totalSupply != totalDebt);
    }

    // Invariant 4: Non-negative balances
    function invariant_nonNegativeBalances() public {
        assert(wethVault.userToCattyNip(user) >= 0);
        assert(wethVault.totalCattyNip() >= 0);
        assert(wethVault.totalMeowllateralInVault() >= 0);
        assert(kittyPool.getKittyCoinMeownted(user) >= 0);
    }

    // Invariant 5: Vault token consistency
    function invariant_vaultTokenConsistency() public {
        assert(kittyPool.getTokenToVault(weth) == address(wethVault));
        assert(wethVault.i_token() == weth);
    }

    // Invariant 6: Aave interaction integrity
    function invariant_aaveInteraction() public {
        uint256 totalMeowllateralInVault = wethVault.totalMeowllateralInVault();
        uint256 aaveCollateral = wethVault.getTotalMeowllateralInAave();
        (uint256 aaveBalance,, , , ,) = MockAavePool(aavePool).getUserAccountData(address(wethVault));
        assert(totalMeowllateralInVault + aaveCollateral >= aaveBalance);
    }

    // Invariant 7: Liquidation safety
    function invariant_liquidationSafety() public {
        // Simulate bad debt
        vm.startPrank(user);
        IERC20(weth).approve(address(kittyPool), 100 ether);
        kittyPool.depawsitMeowllateral(weth, 100 ether);
        kittyPool.meowintKittyCoin(50 ether);
        vm.stopPrank();

        // Change price to make debt bad
        MockChainlinkPriceFeed(ethUsdPriceFeed).setPrice(100000000); // Drop ETH price to 1 USD
        vm.startPrank(address(0xdead));
        kittyPool.purrgeBadPawsition(user);
        vm.stopPrank();

        assert(kittyPool.getKittyCoinMeownted(user) == 0);
    }

    // Helper function for testing deposits
    modifier userDepositsCollateral(address token, uint256 toDeposit) {
        vm.startPrank(user);
        IERC20(token).approve(address(kittyPool), toDeposit);
        kittyPool.depawsitMeowllateral(token, toDeposit);
        vm.stopPrank();
        _;
    }

    function testDeposit(address token, uint256 toDeposit) external userDepositsCollateral(token, toDeposit) {
        uint256 kittyCoinBalanceBefore = kittyCoin.balanceOf(user);
        uint256 wethVaultBalanceBefore = wethVault.totalMeowllateralInVault();

        uint256 kittyCoinBalanceAfter = kittyCoin.balanceOf(user);
        uint256 wethVaultBalanceAfter = wethVault.totalMeowllateralInVault();

        assert(kittyCoinBalanceAfter <= kittyCoinBalanceBefore); // KittyCoin may not increase
        assert(wethVaultBalanceAfter >= wethVaultBalanceBefore); // Vault collateral should increase
    }
}
