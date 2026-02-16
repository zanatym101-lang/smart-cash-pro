/* eslint-disable no-console */
const { remote } = require('webdriverio');

function requireEnv(name) {
  const value = process.env[name];
  if (!value || !value.trim()) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value.trim();
}

async function main() {
  const username = requireEnv('SAUCE_USERNAME');
  const accessKey = requireEnv('SAUCE_ACCESS_KEY');

  // You can replace this full object with the exact "capabilities" snippet from Sauce UI.
  const capabilities = {
    platformName: 'Android',
    'appium:automationName': 'UiAutomator2',
    'appium:app': process.env.SAUCE_APP || 'storage:filename=app-release.apk',
    'appium:deviceName':
      process.env.SAUCE_DEVICE_NAME || 'Android GoogleAPI Emulator',
    'appium:platformVersion': process.env.SAUCE_PLATFORM_VERSION || '12.0',
    'appium:autoGrantPermissions': true,
    'appium:newCommandTimeout': 240,
    'appium:appPackage': process.env.APP_PACKAGE || 'com.smartcashpro.app',
    'appium:appActivity':
      process.env.APP_ACTIVITY || 'com.smartcashpro.app.MainActivity',
    'sauce:options': {
      name: process.env.SAUCE_TEST_NAME || 'Smart Cash Pro Smoke',
      build: process.env.SAUCE_BUILD_NAME || 'appium-build-P5D9R',
      deviceOrientation: process.env.SAUCE_DEVICE_ORIENTATION || 'PORTRAIT',
      appiumVersion: '2.0.0'
    }
  };

  const driver = await remote({
    protocol: 'https',
    hostname:
      process.env.SAUCE_REGION_HOST || 'ondemand.eu-central-1.saucelabs.com',
    port: 443,
    path: '/wd/hub',
    user: username,
    key: accessKey,
    capabilities,
    logLevel: process.env.WDIO_LOG_LEVEL || 'info'
  });

  let passed = false;
  let reason = '';
  try {
    await driver.pause(5000);

    // Minimal smoke: app is launched and page source is non-empty.
    const source = await driver.getPageSource();
    if (!source || source.length < 100) {
      throw new Error('App launched but page source looks empty.');
    }

    await driver.saveScreenshot('sauce_smoke_launch.png');
    passed = true;
    reason = 'App launched successfully and UI tree is available.';
    console.log(reason);
  } catch (err) {
    reason = err?.message || String(err);
    console.error('Smoke test failed:', reason);
    throw err;
  } finally {
    try {
      await driver.execute('sauce:job-result=' + (passed ? 'passed' : 'failed'));
      await driver.execute(
        'sauce:context=' + (reason || (passed ? 'passed' : 'failed'))
      );
    } catch (_) {}
    await driver.deleteSession();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
