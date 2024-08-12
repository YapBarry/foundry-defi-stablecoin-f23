// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = config
            .activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////////////
    // Constructor Tests /////
    //////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPricefeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ////////////////////
    // Price Tests /////
    ////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $2000 /ETH, $100
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ////////////////////////////////
    // depositCollateral Tests /////
    ////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    // Test 1
    function testDepositCollateralEmitsCollateralDepositedEvent() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, true, true);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);

        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // no test for btc?

    ///////////////////////
    // mintDsc Tests /////
    //////////////////////

    // Test 2
    function testDSCMintedIsCorrectlyAddedToMintersBalance()
        public
        depositedCollateral
    {
        vm.startPrank(USER);
        dsce.mintDsc(AMOUNT_COLLATERAL);
        vm.stopPrank();
        assertEq(dsce.getDSCMinted(USER), AMOUNT_COLLATERAL);
    }

    ///////////////////////
    // liquidate Tests ////
    //////////////////////

    // Test 3 (WIP)
    function testLiquidateFunctionRevertsIfUserHealthFactorIsAboveMinHealthFactor()
        public
    {
        // do and compare against line 419 of Patrick's video
        vm.startPrank(LIQUIDATOR);

        vm.stopPrank();
    }

    // function liquidate(
    //     address collateral,
    //     address user,
    //     uint256 debtToCover
    // ) external moreThanZero(debtToCover) nonReentrant {
    //     // need to check health factor of the user
    //     uint256 startingUserHealthFactor = _healthFactor(user);
    //     if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
    //         revert DSCEngine__HealthFactorOk();
    //     }
    //     // We want to burn their DSC "debt"
    //     // And take their collateral
    //     // Bad user: $140 ETH, $100 DSC
    //     // debtToCover = $100
    //     // $100 of DSC == ??? ETH?
    //     // 0.05 ETH
    //     uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
    //         collateral,
    //         debtToCover
    //     );
    //     // And give them a 10% bonus
    //     // So we are giving the liquidator $110 of WETH for 100 DSC
    //     // We should implememnt a feature to liquidate in the event the protocol is insolvent
    //     // And sweep extra amounts into a treasury

    //     // 0.05 eth * .1 = 0.005. Getting 0.055 ETH
    //     uint256 bonusCollateral = (tokenAmountFromDebtCovered *
    //         LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
    //     uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
    //         bonusCollateral;
    //     // We need to burn the dsc
    //     _burnDsc(debtToCover, user, msg.sender);

    //     uint256 endingUserHealthFactor = _healthFactor(user);
    //     if (endingUserHealthFactor <= startingUserHealthFactor) {
    //         revert DSCEngine__HealthFactorNotImproved();
    //     }
    //     // call revert if by paying for the liquidation, the msg.sender's health factor
    //     // actually worsened
    //     _revertIfHealthFactorIsBroken(msg.sender);
    // }
}
