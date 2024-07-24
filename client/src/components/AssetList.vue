<script lang="ts">
import { Token, displayValue } from '../utils.ts';

export default {
  props: ['wrappedTokenValue', 'tokens', 'setWrapToken'],

  setup({ wrappedTokenValue, tokens, setWrapToken }) {

    return {
      displayValue,
    };
  },
};
</script>

<template>
  <div>
  <h3>NFTs</h3>
    <table v-if="tokens !== null">
      <tbody>
      <tr v-for="token in tokens.filter(t => t.possible_spam === false)">
        <td>
          <img v-if="token.thumbnail" height="32px" :src="token.thumbnail" />
          <div v-else style="display: flex; align-items: center; justify-content: center; outline: 1px solid black; height: 32px; width: 32px">
            <span>?</span>
          </div>
        </td>
        <td>
          <span>{{ token.symbol }}</span>
        </td>
        <td>
          <span>{{ token.name }}</span>
        </td>
        <td>
          <input
            type="number"
            :value="wrappedTokenValue(token)"
            :max="displayValue(token, token.balance)"
            @input="event => setWrapToken(token, event.target.value)"
          />
          <span :title="displayValue(token, token.balance)">of {{ (displayValue(token, token.balance)).toFixed(4) }}</span>
        </td>
      </tr>
      </tbody>
    </table>
  </div>
</template>

