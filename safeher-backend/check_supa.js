const axios = require('axios');

const SUPA_URL = 'https://lffrcldhbesywswwjqnu.supabase.co';
const ANON_KEY = 'sb_publishable_arkbVnMWBz7syDVEDEOGRQ_xr_GyHsO';

async function main() {
    try {
        const res = await axios.get(`${SUPA_URL}/rest/v1/incidents?select=*`, {
            headers: {
                'apikey': ANON_KEY,
                'Authorization': `Bearer ${ANON_KEY}`
            }
        });
        console.log('Incidents count:', res.data.length);
        console.log('First incident:', JSON.stringify(res.data[0], null, 2));
    } catch (e) {
        console.error('Error fetching incidents:', e.response?.data || e.message);
    }
}

main();
