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

type Asset = {
  name: string,
  ticker: string,
  logo_url: string,
  price: string,
  category: "ERC20"|"ERC721"|"ERC1155",
  address: string,
  id: string,
  amount: string,
  decimals: number,
}

export default {
  setup() {
    //const network = ref<string>("sepolia");
    const network = ref<string>("eth");
    const address = ref<Address>(null);
    const assets = ref<Asset[]|null>(null);
    const fetchError = ref<bool>(false);

    async function connect() {
      const [newAddress] = await client.requestAddresses();
      address.value = newAddress;

      console.log(address.value);

      try {
        const data = fetch(`http://localhost:10000/api/assets/${network.value}/${address.value}`);
        const jsonData = data.json();
        assets.value = jsonData.assets;
      }
      catch {
        fetchError.value = true;
      }
    }

    return {
      address,
      connect,
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
</template>
