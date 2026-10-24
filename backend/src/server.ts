import { createApp } from './app';
import { config } from './lib/config';

createApp().listen(config.port, () => {
  console.log(`OnePe POS API listening on http://localhost:${config.port}`);
});
