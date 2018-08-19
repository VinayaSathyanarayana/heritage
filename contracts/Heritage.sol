pragma solidity 0.4.24;

import "zeppelin-solidity/contracts/ownership/Ownable.sol";
import "zeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "zeppelin-solidity/contracts/lifecycle/Destructible.sol";
import "./Managed.sol";
import "./DonationCore.sol";

// Todo
// Destroy Proxy once goal is met
contract Proxy {
  Heritage heritage;
  uint256 donationId;

  constructor(uint256 _donationId) public payable {
    require(msg.value == 0);

    donationId = _donationId;
    heritage = Heritage(msg.sender);
  }

  function() public payable {
    heritage.proxyDonation.value(msg.value)(donationId, msg.sender);
  }
}


contract Heritage is Ownable, Pausable, Destructible, Managed, DonationCore {
  bool public issueDonationEnabled = false;
  mapping (address => bool) public isProxy;

  modifier issueDonationIsEnabled() {
    require(issueDonationEnabled);
    _;
  }

  modifier onlyProxy() {
    require(isProxy[msg.sender]);
    _;
  }

  constructor(bool enableIssueDonation) public payable {
    require(msg.value == 0);

    issueDonationEnabled = enableIssueDonation;

    _createDonation("Genesis Donation", 0, this, "");
  }

  // Do not accept any transactions that send Ether.
  function() external {
  }

  // Cannot prevent Ether from being mined/self-destructed to this contract
  // reclaim lost Ether.
  function reclaimEther() external onlyOwner {
    owner.transfer(address(this).balance);
  }

  function createDonation(
    string _description,
    uint256 _goal,
    address _beneficiary,
    string _taxId
  )
    public
    onlyManagers
    whenNotPaused
    returns (uint256)
  {
    require(donations.length < 4294967296 - 1); // 2^32-1
    return _createDonation(_description, _goal, _beneficiary, _taxId);
  }

  function createDAIDonation(
    string _description,
    uint256 _goal,
    address _beneficiary,
    string _taxId
  )
    public
    onlyManagers
    whenNotPaused
    returns (uint256)
  {
    require(donations.length < 4294967296 - 1); // 2^32-1
    return _createDAIDonation(_description, _goal, _beneficiary, _taxId);
  }

  function proxyDonation(
    uint256 _donationId,
    address _donor
  )
    public
    payable
    onlyProxy
  {
    _makeDonation(_donationId, msg.value, _donor);
  }

  function createDonationProxy(uint32 _donationId)
    public
    returns (address proxyAddress)
  {
    require(_donationId > 0);
    require(_donationId < totalDonations);
    Proxy p = new Proxy(_donationId);
    isProxy[p] = true;
    return p;
  }

  // Make a donation based on Id.
  // Donate directly or proxy through another donation.
  function makeDonation(uint256 _donationId)
    public
    payable
    whenNotPaused
    returns (uint256)
  {
    // Must make a donation
    require(msg.value > 0);

    uint256 totalDonations = donations.length;
    // Cannot delete Genesis
    require(_donationId > 0);
    // Must delete an existing donation
    require(_donationId < totalDonations);
    // 2^32-1
    require(totalDonations < 4294967296 - 1);
    // Lookup the original donation
    uint32 donationId = donations[_donationId].donationId;
    // Is not a token donation
    require(!isDai[donationId]);

    // Cannot donate to deleted token/null address
    require(donationBeneficiary[donationId] != address(0));
    // A goal of 0 is uncapped
    if (donationGoal[donationId] > 0) {
      // It must not have reached it's goal
      require(donationRaised[donationId] < donationGoal[donationId]);
    }

    // Donate through another person's donation
    if (donationId != _donationId) {
      donationRaised[_donationId] += msg.value;
    }
    // Send the tx value to the charity
    donationBeneficiary[donationId].transfer(msg.value);
    // Update the amount raised for the donation
    donationRaised[donationId] += msg.value;
    // Update the total amount the contract has raised
    totalRaised += msg.value;

    return _makeDonation(donationId, msg.value, msg.sender);
  }

  // Make a DAI donation based on Id.
  // Donate directly or proxy through another donation.
  function makeDAIDonation(uint32 _donationId, uint256 _amount)
    public
    payable
    whenNotPaused
    returns (uint256)
  {
    // Cannot donate to Genesis
    require(_donationId > 0);
    // Must donate to an existing donation
    require(_donationId < donations.length);
    // 2^32-1
    require(donations.length < 4294967296 - 1);
    // Lookup the original donation
    uint32 donationId = donations[_donationId].donationId;
    // Must be a DAI donation token
    require(isDai[donationId]);
    // Cannot donate to deleted token/null address
    require(donationBeneficiary[donationId] != address(0));
    // A goal of 0 is uncapped
    if (donationGoal[donationId] > 0) {
      // It must not have reached it's goal
      require(donationRaised[donationId] < donationGoal[donationId]);
    }

    // Donate through another person's donation
    if (donationId != _donationId) {
      donationRaised[_donationId] += _amount;
    }
    // Send the tx value to the charity
    _transferDai(msg.sender, donationBeneficiary[donationId], _amount);
    // Update the amount raised for the donation
    donationRaised[donationId] += _amount;
    // Update the total amount the contract has raised
    totalDAIRaised += _amount;

    return _makeDonation(donationId, _amount, msg.sender);
  }

  // Managers may issue donations directly. A way to accept fiat donations
  // and credit an address. Optional -- disable/enable at deployment.
  // Does not effect contract totals. Must issue to a created donation.
  function issueDonation(uint256 _donationId, uint256 _amount, address _donor)
    public
    onlyManagers
    issueDonationIsEnabled
    whenNotPaused
    returns (uint256)
  {
    uint256 totalDonations = donations.length;
    // Cannot delete Genesis
    require(_donationId > 0);
    // Must delete an existing donation
    require(_donationId < totalDonations);
    // 2^32-1
    require(totalDonations < 4294967296 - 1);
    // Lookup the original donation
    uint32 donationId = donations[_donationId].donationId;

    return _issueDonation(donationId, _amount, _donor);
  }

  function deleteDonation(uint256 _donationId)
    public
    onlyOwner
  {
    uint256 totalDonations = donations.length;
    // Cannot delete Genesis
    require(_donationId > 0);
    // Must delete an existing donation
    require(_donationId < totalDonations);
    // 2^32-1
    require(totalDonations < 4294967296 - 1);
    _deleteDonation(_donationId);
  }
}