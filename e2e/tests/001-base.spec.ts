import {test, expect} from '@playwright/test';

test('non-prod indicator is off by default', async ({page}) => {
    await page.goto('/wiki/Main_Page');
    await expect(page.locator('.wikiteq-nonprod-label')).toHaveCount(0);
});

test('has successful installation message', async ({page}) => {
    await page.goto('/wiki/Main_Page');
    await expect(page.locator('#content')).toContainText(/MediaWiki has been installed/);
});

test('has a login link', async ({page}) => {
    await page.goto('/wiki/Main_Page');
    await expect(page.locator('#pt-login')).toContainText(/Log in/);
});

test('has a signup link', async ({page}) => {
    await page.goto('/wiki/Main_Page');
    await expect(page.locator('#pt-createaccount')).toContainText(/Create account/);
});

test('has vector skin enabled by default', async ({page}) => {
    await page.goto('/wiki/Main_Page');
    await expect(page.locator('body')).toHaveClass(/skin-vector-legacy/);
});

test('edit for anonymous is enabled by default', async ({page}) => {
    await page.goto('/wiki/Main_Page');
    await expect(page.locator('#ca-edit')).toBeVisible();
});

test('visual editor is enabled', async ({page}) => {
    await page.goto('/wiki/Main_Page');
    await expect(page.locator('#ca-ve-edit')).toBeVisible();
});

test('special version works', async ({page}) => {
    await page.goto('/wiki/Special:Version');
    await expect(page.locator('#firstHeading')).toContainText(/Version/);
});

test('special version software installed', async ({page}) => {
    await page.goto('/wiki/Special:Version');
    await expect(page.locator('#sv-software')).toContainText(/PHP/);
    await expect(page.locator('#sv-software')).toContainText(/MySQL/);
    await expect(page.locator('#sv-software')).toContainText(/ICU/);
    await expect(page.locator('#sv-software')).toContainText(/LuaSandbox/);
    await expect(page.locator('#sv-software')).toContainText(/Lua/);
});

test('API endpoint works', async ({page}) => {
    await page.goto('/w/api.php');
    await expect(page).toHaveTitle(/MediaWiki API help/)
});

test('robots.txt is in place', async ({page}) => {
    await page.goto('/robots.txt');
    //let contents = await page.content();
    //expect(contents).toContain(/User-agent/);
    await expect(page.locator('pre')).toContainText(/User-agent/);
});

// Can be enabled later
// test('robots.txt contains sitemap instruction', async ({page}) => {
//     await page.goto('/robots.txt');
//     await expect(page.locator('pre')).toContainText(/Sitemap/);
// });
