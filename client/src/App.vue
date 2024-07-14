<script lang="ts">
import { RouterLink, RouterView } from 'vue-router';
import HelloWorld from './components/HelloWorld.vue';
import { type Address, createWalletClient, custom } from 'viem';
import { sepolia } from 'viem/chains';
import { ref, onMounted } from 'vue';

const client = createWalletClient({
  chain: sepolia,
  transport: custom(window.ethereum!),
});

type Token = {
  token_address: string,
  symbol: string,
  name: string,
  logo: string|null,
  thumbnail: string|null,
  decimals: number,
  balance: string,
  possible_spam: bool,
  verified_contract: bool,
};

type NFT = {
  token_id: string,
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

type Assets = {
  tokens: Token[],
  nfts: NFT[],
};

export default {
  setup() {
    //const network = ref<string>("sepolia");
    const network = ref<string>("eth");
    const address = ref<Address>(null);
    const assets = ref<Assets|null>(null);
    const fetchError = ref<string|null>(null);

    async function connect() {
      const [newAddress] = await client.requestAddresses();
      address.value = newAddress;

      console.log(address.value);

      await fetchAssets();
    }

    async function fetchAssets() {
      try {
        const data = await fetch(`http://localhost:10000/api/assets/${network.value}/${address.value}`);
        const jsonData = data.json();
        assets.value = jsonData.assets;
        fetchError.value = null;

        console.log(assets.value);
      }
      catch {
        fetchError.value = "fetch assets error";
      }
    }

    async function refreshAssets() {
      try {
        await fetch(`http://localhost:10000/api/assets/${network.value}/${address.value}/refresh`);
        fetchError.value = null;

        await fetchAssets();
      }
      catch {
        fetchError.value = "refresh server error";
      }
    }

    return {
      address,
      connect,
      fetchAssets,
      refreshAssets,
    }

  },
  mounted() {
    console.log("mounted");
  },
};
</script>

<template>
  <button v-if="address === null" @click="connect()">Connect</button>
  <div v-else>{{ address }}</div>
  <button @click="refreshAssets()">Refresh Assets</button>
</template>
