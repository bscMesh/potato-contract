// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;
import "./libs/BEP20.sol";
import "./libs/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract FairIDOWithBNB is ReentrancyGuard, Ownable {
  using SafeMath for uint256;
  using SafeBEP20 for IBEP20;

  // Info of each user.
  struct UserInfo {
      uint256 amount;   // How many BNB the user has provided.
      bool claimed;  // default false
  }
  // The offering token
  IBEP20 public offeringToken;
  // The block number when fair ido starts
  uint256 public startBlock;
  // The block number when fair ido ends
  uint256 public endBlock;
  // total amount of raising BNB need to be raised
  uint256 public raisingAmount;
  // total amount of offeringToken that will offer
  uint256 public offeringAmount;
  // total amount of raising tokens that have already raised
  uint256 public totalAmount;
  // address => amount
  mapping (address => UserInfo) public userInfo;
  // participators
  address[] public addressList;

  event Deposit(address indexed user, uint256 amount);
  event Harvest(address indexed user, uint256 offeringAmount, uint256 excessAmount);

  constructor(
      IBEP20 _offeringToken,
      uint256 _startBlock,
      uint256 _endBlock,
      uint256 _offeringAmount,
      uint256 _raisingAmount
  ) public {
      offeringToken = _offeringToken;
      startBlock = _startBlock;
      endBlock = _endBlock;
      offeringAmount = _offeringAmount;
      raisingAmount= _raisingAmount;
      totalAmount = 0;
  }

  function setOfferingAmount(uint256 _offerAmount) public onlyOwner {
    require (block.number < startBlock, 'no');
    offeringAmount = _offerAmount;
  }

  function setRaisingAmount(uint256 _raisingAmount) public onlyOwner {
    require (block.number < startBlock, 'no');
    raisingAmount = _raisingAmount;
  }

  receive() external payable{
    require(msg.value > 0, 'need amount > 0');
    require (block.number > startBlock && block.number < endBlock, 'not ifo time');
    if (userInfo[msg.sender].amount == 0) {
      addressList.push(address(msg.sender));
    }
	userInfo[msg.sender].amount = userInfo[msg.sender].amount.add(msg.value);
	totalAmount = totalAmount.add(msg.value);
    emit Deposit(msg.sender, msg.value);
  }

  function harvest() public nonReentrant {
    require (block.number > endBlock, 'not harvest time');
    require (userInfo[msg.sender].amount > 0, 'have you participated?');
    require (!userInfo[msg.sender].claimed, 'nothing to harvest');
    uint256 offeringTokenAmount = getOfferingAmount(msg.sender);
    uint256 refundingTokenAmount = getRefundingAmount(msg.sender);
    if (offeringTokenAmount > 0) {
      offeringToken.safeTransfer(address(msg.sender), offeringTokenAmount);
    }
    if (refundingTokenAmount > 0) {
	  address payable refundAccount = payable(msg.sender);
	  refundAccount.transfer(refundingTokenAmount);
    }
    userInfo[msg.sender].claimed = true;
    emit Harvest(msg.sender, offeringTokenAmount, refundingTokenAmount);
  }

  function hasHarvest(address _user) external view returns(bool) {
      return userInfo[_user].claimed;
  }

  // allocation 100000 means 0.1(10%), 1 meanss 0.000001(0.0001%), 1000000 means 1(100%)
  function getUserAllocation(address _user) public view returns(uint256) {
    return userInfo[_user].amount.mul(1e12).div(totalAmount).div(1e6);
  }

  // get the amount of IFO token you will get
  function getOfferingAmount(address _user) public view returns(uint256) {
    if (totalAmount > raisingAmount) {
      uint256 allocation = getUserAllocation(_user);
      return offeringAmount.mul(allocation).div(1e6);
    }
    else {
      // userInfo[_user] / (raisingAmount / offeringAmount)
      return userInfo[_user].amount.mul(offeringAmount).div(raisingAmount);
    }
  }

  // get the amount of lp token you will be refunded
  function getRefundingAmount(address _user) public view returns(uint256) {
    if (totalAmount <= raisingAmount) {
      return 0;
    }
    uint256 allocation = getUserAllocation(_user);
    uint256 payAmount = raisingAmount.mul(allocation).div(1e6);
    return userInfo[_user].amount.sub(payAmount);
  }

  function getAddressListLength() external view returns(uint256) {
    return addressList.length;
  }

  function finalWithdraw(uint256 _bnbAmount, uint256 _offerAmount) public onlyOwner {
    require (_bnbAmount <= address(this).balance, 'no enough bnb');
    require (_offerAmount <= offeringToken.balanceOf(address(this)), 'no enough token 1');
    if(_offerAmount > 0) {
      offeringToken.safeTransfer(address(msg.sender), _offerAmount);
    }
    if(_bnbAmount > 0) {
	  address payable dev = payable(owner());
	  dev.transfer(_bnbAmount);
    }
  }
  
  //in case someone transfer fund in accident
  function inCaseTokensGetStuck(IBEP20 _token, uint256 _amount) public onlyOwner{
	require(_token != offeringToken, "!safe");
    IBEP20(_token).safeTransfer(msg.sender, _amount);
  }
  
}