<script lang="ts">
export default {
  props: ['nfts', 'setWrapNFT', 'wrappedNFT'],

  setup({ nfts, setWrapNFT, wrappedNFT }) {
    return {
      nfts,
      setWrapNFT,
      wrappedNFT,
    };
  },
};
</script>

<template>
  <div>
  <h3>Tokens</h3>
    <table v-if="nfts !== null">
    <tbody>
      <tr v-for="nft in nfts.filter(n => n.possible_spam === false)">
        <td>
          <img v-if="nft.collection_logo" height="32px" :src="nft.collection_logo" />
          <div v-else style="display: flex; align-items: center; justify-content: center; outline: 1px solid black; height: 32px; width: 32px">
            <span>?</span>
          </div>
        </td>
        <td>
          <span>{{ nft.symbol }}</span>
        </td>
        <td>
          <span>{{ nft.name }}</span>
        </td>
        <td>
          <button v-if="!wrappedNFT(nft)" @click="setWrapNFT(nft, true)">Add</button>
          <button v-else @click="setWrapNFT(nft, false)">Remove</button>
        </td>
      </tr>
    </tbody>
    </table>
  </div>
</template>
