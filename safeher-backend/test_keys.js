const axios = require('axios');

const keys = [
  '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',
  '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'
];

async function checkKey(key) {
  try {
    const response = await axios.post(
      'https://openrouter.ai/api/v1/chat/completions',
      {
        model: 'openai/gpt-4o-mini',
        messages: [{ role: 'user', content: 'hello' }],
        max_tokens: 1
      },
      {
        headers: {
          'Authorization': `Bearer ${key}`,
          'Content-Type': 'application/json'
        }
      }
    );
    console.log(`Key ${key.substring(0, 10)}...: VALID`);
  } catch (error) {
    console.log(`Key ${key.substring(0, 10)}...: INVALID - ${JSON.stringify(error.response?.data || error.message)}`);
  }
}

async function run() {
  for (const key of keys) {
    await checkKey(key);
  }
}

run();
