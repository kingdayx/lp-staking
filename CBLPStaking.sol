// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "lib/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "./CBNFTPack.sol";



contract QuickswapStakingPool is ERC1155, Ownable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    enum RewardType { None, NFTPack, RegularNFT }

    struct Pool {
        address token0;
        address token1;
        RewardType rewardType;
        address rewardNFTAddress;
        uint256 rewardNFTId;
        uint256[] rarityProbabilities;
        uint256 totalStaked;
    }

    IUniswapV2Router02 public immutable quickswapRouter;
    IUniswapV2Factory public immutable quickswapFactory;
    IERC6551Registry public immutable registry;
    NFTPack public immutable nftPack;

    mapping(uint256 => Pool) public pools;
    uint256 public nextPoolId;

    constructor(
        address _quickswapRouter,
        address _quickswapFactory,
        address _nftPack,
        address _registry
    ) ERC1155("") Ownable() {
        quickswapRouter = IUniswapV2Router02(_quickswapRouter);
        quickswapFactory = IUniswapV2Factory(_quickswapFactory);
        nftPack = NFTPack(_nftPack);
            registry = IERC6551Registry(_registry);
        nextPoolId = 1;
    }

function createPool(
    address _token0,
    address _token1,
    RewardType _rewardType,
    address _rewardNFTAddress,
    uint256 _rewardNFTId,
    uint256[] memory _rarityProbabilities
) external onlyOwner {
    require(_token0 != address(0) && _token1 != address(0), "Invalid token addresses");
    require(_token0 != _token1, "Tokens must be different");
    require(_rewardType != RewardType.None, "Invalid reward type");
    require(_rewardNFTAddress != address(0), "Invalid reward NFT address");

    if (_rewardType == RewardType.NFTPack) {
        require(_rarityProbabilities.length > 0, "Rarity probabilities cannot be empty");
        uint256 totalProbability;
        for (uint256 i = 0; i < _rarityProbabilities.length; i++) {
            totalProbability += _rarityProbabilities[i];
        }
        require(totalProbability == 100, "Total probability must be 100");
    } else {
        _rarityProbabilities = new uint256[](0);
    }

    pools[nextPoolId] = Pool({
        token0: _token0,
        token1: _token1,
        rewardType: _rewardType,
        rewardNFTAddress: _rewardNFTAddress,
        rewardNFTId: _rewardNFTId,
        rarityProbabilities: _rarityProbabilities,
        totalStaked: 0
    });

    nextPoolId++;
}


 function stake(uint256 _poolId, uint256 _amount) external {
    Pool storage pool = pools[_poolId];
    require(pool.token0 != address(0) && pool.token1 != address(0), "Invalid pool");

    address pair = quickswapFactory.getPair(pool.token0, pool.token1);
    require(pair != address(0), "Pair does not exist");

    IERC20(pair).safeTransferFrom(msg.sender, address(this), _amount);
    pool.totalStaked += _amount;

    _mint(msg.sender, _poolId, _amount, "");
}

  function withdraw(uint256 _poolId, uint256 _amount) external {
    Pool storage pool = pools[_poolId];
    require(pool.token0 != address(0) && pool.token1 != address(0), "Invalid pool");
    require(balanceOf(msg.sender, _poolId) >= _amount, "Insufficient balance");

    _burn(msg.sender, _poolId, _amount);
    pool.totalStaked -= _amount;

    address pair = quickswapFactory.getPair(pool.token0, pool.token1);
    require(pair != address(0), "Pair does not exist");

    IERC20(pair).safeTransfer(msg.sender, _amount);
}

  function claimReward(uint256 _poolId) external {
    Pool storage pool = pools[_poolId];
    require(pool.token0 != address(0) && pool.token1 != address(0), "Invalid pool");
    require(balanceOf(msg.sender, _poolId) > 0, "No staked balance");

    uint256 reward = balanceOf(msg.sender, _poolId);
    _burn(msg.sender, _poolId, reward);
    pool.totalStaked -= reward;

       if (pool.rewardType == RewardType.NFTPack) {
        uint256 randomNumber = _getRandomNumber(100);
        uint256 cumulativeProbability;

        for (uint256 i = 0; i < pool.rarityProbabilities.length; i++) {
            cumulativeProbability += pool.rarityProbabilities[i];
            if (randomNumber <= cumulativeProbability) {
              nftPack.mint(msg.sender, pool.rewardNFTId, 1);
                break;
            }
        }
    } else if (pool.rewardType == RewardType.RegularNFT) {
        IERC721(pool.rewardNFTAddress).transferFrom(address(this), msg.sender, pool.rewardNFTId);
    }
}

    function _getRandomNumber(uint256 _maxNumber) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % _maxNumber;
    }
}