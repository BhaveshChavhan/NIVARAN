const axios = require('axios');

const apiKey = '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';

async function testOpenRouter() {
    try {
        console.log('Testing OpenRouter connection...');
        const response = await axios.post(
            'https://openrouter.ai/api/v1/chat/completions',
            {
                model: 'openai/gpt-4o-mini',
                messages: [{ role: 'user', content: 'Say hello' }],
            },
            {
                headers: {
                    'Authorization': `Bearer ${apiKey}`,
                    'Content-Type': 'application/json',
                    'HTTP-Referer': 'https://nivaran.app',
                    'X-Title': 'Nivaran',
                },
                timeout: 10000
            }
        );
        console.log('Success!', response.data);
    } catch (error) {
        console.error('Error:', error.response?.data || error.message);
    }
}

testOpenRouter();
