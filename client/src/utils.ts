import { encodeAbiParameters, getAbiItem } from 'viem';

import tokenBundlerABI from './token_bundler.json';

const createABI = getAbiItem({
  abi: tokenBundlerABI,
  name: 'create',
});

export type Token = {
  token_address: string,
  symbol: string,
  name: string,
  logo: string|null,
  thumbnail: string|null,
  decimals: number,
  balance: BigInt,
  possible_spam: bool,
  verified_contract: bool,
};

export type NFT = {
  token_id: BigInt,
  token_address: string,
  contract_type: string,
  last_metadata_sync: string,
  last_token_uri_sync: string,
  name: string,
  symbol: string,
  token_hash: string,
  token_uri: string,
  verified_collection: bool,
  possible_spam: bool,
  collection_logo: string,
  collection_banner_image: string,
};

export type Assets = {
  tokens: Token[],
  nfts: NFT[],
};

export enum Category {
  ERC20,
  ERC721,
  ERC1155,
  CryptoKitties,
};

function toCategory(s: string): Category {
  switch (s) {
    case "ERC20":
      return Category.ERC20;
    case "ERC721":
      return Category.ERC721;
    case "ERC1155":
      return Category.ERC1155;
    case "CRYPTOKITTIES":
      return Category.CryptoKitties;
    default:
      throw "Invalid category name: " + s;
  }
}

export function displayValue(token: Token, value: number): number {
  return value / (10 ** token.decimals);
}

export function encodeAssets(
  toWrapTokens: {[key: string]: BigInt},
  toWrapNFTs: {[key: string]: NFT},
) {
  const params = {
    ...Object.entries(toWrapTokens).map(([key, amount]) => ({
      category: Category.ERC20,
      address: key,
      id: 0,
      amount: amount,
    })),
    ...Object.entries(toWrapNFTs).map(([_, nft]) => ({
      category: toCategory(nft.contract_type),
      address: nft.token_address,
      id: nft.token_id,
      amount: 0,
    })),
  };

  console.log(createABI, params);

  return encodeAbiParameters(
    createABI.inputs,
    params,
  );
}
