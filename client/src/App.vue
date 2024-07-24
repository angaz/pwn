<script lang="ts">
import { type Address, createWalletClient, custom, getAbiItem } from 'viem';
import { sepolia } from 'viem/chains';
import { ref, onMounted } from 'vue';
import { Token, NFT, Assets, displayValue, encodeAssets } from './utils.ts';
import AssetList from './components/AssetList.vue';
import NFTList from './components/NFTList.vue';
import tokenBundlerABI from './token_bundler.json';

const client = createWalletClient({
  chain: sepolia,
  transport: custom(window.ethereum!),
});

const baseURL = process.env.NODE_ENV === "production" ? "/api" : "http://localhost:10000/api";

export default {
  components: {
    AssetList,
    NFTList,
  },

  setup() {
    //const network = ref<string>("sepolia");
    const network = ref<string>("eth");
    const address = ref<Address|null>(null);
    const assets = ref<Assets|null>(null);
    const fetchError = ref<string|null>(null);
    const toWrapTokens = ref<{[key: string]: BigInt}>({});
    const toWrapNFTs = ref<{[key: string]: NFT}>({});

    async function connect() {
      const [newAddress] = await client.requestAddresses();
      address.value = newAddress;

      await fetchAssets();
    }

    async function fetchAssets() {
      try {
        const data = await fetch(`${baseURL}/assets/${network.value}/${address.value}`);
        assets.value = await data.json();
        fetchError.value = null;
      }
      catch {
        fetchError.value = "fetch assets error";
      }
    }

    async function refreshAssets() {
      try {
        await fetch(`${baseURL}/assets/${network.value}/${address.value}/refresh`);
        fetchError.value = null;

        await fetchAssets();
      }
      catch {
        fetchError.value = "refresh server error";
      }
    }

    function setWrapToken(token: Token, value: string) {
      const newValue = Math.min(parseFloat(value) * 10 ** token.decimals, token.balance);
      console.log(token.token_address, value, newValue);

      toWrapTokens.value[token.token_address] = newValue != 0 ? newValue : undefined;
    }

    function setWrapNFT(nft: NFT, add: boolean) {
      const key = `${nft.token_address}_${nft.token_id}`;
      console.log("wrap nft", key, add);

      toWrapNFTs.value[key] = add ? nft : undefined;
    }

    function wrappedTokenValue(token: Token): BigInt {
      if (token.token_address in toWrapTokens.value) {
        return displayValue(token, toWrapTokens.value[token.token_address]);
      }

      return 0n;
    }

    function wrappedNFT(nft: NFT): boolean {
      const key = `${nft.token_address}_${nft.token_id}`;

      if (key in toWrapNFTs.value) {
        return toWrapNFTs.value[key];
      }

      return false;
    }

    // TODO: call Approve for all assets before bundling.
    async function wrap() {
      try {
        const args = encodeAssets(toWrapTokens.value, toWrapNFTs.value);
      
        const { request } = await client.simulateContract({
          account: address.value,
          address: "0x19e3293196aee99BB3080f28B9D3b4ea7F232b8d",
          abi: tokenBundlerABI,
          functionName: 'create',
          args: args,
        });

        await client.writeContract(request);
        fetchError.value = null;

        await refreshAssets();
      }
      catch (e) {
        console.log(e);
        fetchError.value = "send transaction error";
      }
    }

    return {
      address,
      assets,
      connect,
      fetchAssets,
      refreshAssets,
      setWrapToken,
      wrappedTokenValue,
      setWrapNFT,
      wrappedNFT,
      fetchError,
      wrap,
    };

  },
  mounted() {
    console.log("mounted");
  },
};
</script>

<template>
  <div style="display: flex; flex-direction: column">
    <button v-if="address === null" @click="connect()">Connect</button>
    <div v-else>
      <span>{{ address }}</span>
      <button @click="refreshAssets()">Refresh Assets</button>
    </div>

    <div v-if="fetchError !== null" style="display: flex; flex-direction: column; border: 2px solid red">
      <span>An error occurred</span>
      <span>{{ fetchError }}</span>
    </div>

    <div v-if="assets !== null">
      <AssetList
        :setWrapToken="setWrapToken"
        :wrappedTokenValue="wrappedTokenValue"
        :tokens="assets.tokens"
      />
      <NFTList
        :nfts="assets.nfts"
        :setWrapNFT="setWrapNFT"
        :wrappedNFT="wrappedNFT"
      />

      <button @click="wrap()">Wrap</button>
    </div>
  </div>
</template>
