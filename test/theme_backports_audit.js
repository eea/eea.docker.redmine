#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const baseUrl = process.env.THEME_AUDIT_BASE_URL || "http://0.0.0.0:3000";
const username = process.env.THEME_AUDIT_USERNAME || "admin";
const password = process.env.THEME_AUDIT_PASSWORD || "Admin123!";
const outDir = path.join(process.cwd(), "output", "playwright");

fs.mkdirSync(outDir, { recursive: true });

const requiredChecks = new Set([
  "Anonymous quick-search suppression",
  "Login autofocus",
  "Admin login",
  "Admin wiki links icon class",
  "Simplified project listing",
  "Breadcrumb/header rendering",
  "Hide issue next/previous links",
  "Time entry back_url override",
  "Payment Reference ID UI present"
]);

async function main() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
  const page = await context.newPage();
  page.setDefaultTimeout(15000);

  const results = [];

  async function goto(url, waitForSelector = "body") {
    await page.goto(url, { waitUntil: "domcontentloaded", timeout: 15000 });
    if (waitForSelector) {
      await page.locator(waitForSelector).first().waitFor({ state: "attached", timeout: 15000 });
    }
    await page.waitForTimeout(800);
  }

  async function screenshot(name) {
    await page.screenshot({
      path: path.join(outDir, name),
      fullPage: true
    });
  }

  function add(name, status, details = {}) {
    results.push({ name, status, ...details });
  }

  try {
    await goto(baseUrl);
    const anonQuickSearchHidden = await page.evaluate(() => {
      const el = document.querySelector("#quick-search");
      if (!el) {
        return true;
      }
      const style = window.getComputedStyle(el);
      return style.display === "none" || style.visibility === "hidden";
    });
    add("Anonymous quick-search suppression", anonQuickSearchHidden ? "pass" : "fail", {
      titleText: await page.locator("#header h1").innerText().catch(() => null)
    });
    await screenshot("audit-home-anon.png");

    await goto(`${baseUrl}/login`, "#login-form");
    add("Login autofocus", (await page.evaluate(() => document.activeElement && document.activeElement.id)) === "username" ? "pass" : "fail", {
      focusedId: await page.evaluate(() => document.activeElement && document.activeElement.id)
    });
    await screenshot("audit-login.png");

    await page.fill("#username", username);
    await page.fill("#password", password);
    await Promise.all([
      page.waitForLoadState("domcontentloaded"),
      page.click('input[name="login"]')
    ]).catch(() => {});
    await page.waitForTimeout(1200);
    add("Admin login", (await page.locator("#loggedas").count().catch(() => 0)) ? "pass" : "fail", {
      url: page.url()
    });

    await goto(`${baseUrl}/admin`);
    add("Admin wiki links icon class", (await page.locator("a.wiki-links").first().getAttribute("class").catch(() => null)) === "icon wiki-links" ? "pass" : "fail", {
      wikiClass: await page.locator("a.wiki-links").first().getAttribute("class").catch(() => null)
    });
    await screenshot("audit-admin.png");

    await goto(`${baseUrl}/projects`);
    const projectDescriptionsVisible = await page.evaluate(() => {
      const selectors = [
        "#projects-index .wiki.description",
        "#projects-index ul.projects > li > p",
        "#projects-index ul.projects > li > div > p"
      ];
      const nodes = selectors.flatMap((selector) => Array.from(document.querySelectorAll(selector)));
      return nodes.filter((node) => {
        const style = window.getComputedStyle(node);
        return style.display !== "none" && style.visibility !== "hidden" && node.textContent.trim().length > 0;
      }).length;
    });
    const firstProjectHref = await page.locator("#projects-index a.project").first().getAttribute("href").catch(() => null);
    add("Simplified project listing", projectDescriptionsVisible === 0 ? "pass" : "fail", {
      projectDescriptionsVisible,
      firstProjectHref
    });
    await screenshot("audit-projects.png");

    if (firstProjectHref) {
      await goto(`${baseUrl}${firstProjectHref}`);
      add("Breadcrumb/header rendering", (await page.locator("#header h1").innerText().catch(() => null)) ? "pass" : "fail", {
        breadcrumbText: await page.locator("#header h1").innerText().catch(() => null)
      });
      add("Projects box above members", await page.evaluate(() => {
        const members = document.querySelector(".members.box");
        const projects = document.querySelector(".projects.box");
        if (!members || !projects) {
          return "skip";
        }
        return (projects.compareDocumentPosition(members) & Node.DOCUMENT_POSITION_FOLLOWING) ? "pass" : "fail";
      }), {});
      await screenshot("audit-project-page.png");
    } else {
      add("Breadcrumb/header rendering", "skip", { reason: "No project found" });
      add("Projects box above members", "skip", { reason: "No project found" });
    }

    await goto(`${baseUrl}/issues`);
    const firstIssueHref = await page.locator("table.issues td.subject a, a.issue").first().getAttribute("href").catch(() => null);
    add("Issue page source available", firstIssueHref ? "pass" : "skip", { firstIssueHref });

    if (firstIssueHref) {
      await goto(`${baseUrl}${firstIssueHref}`);
      add("Hide issue next/previous links", await page.evaluate(() => {
        const el = document.querySelector(".issue.details .next-prev-links, .next-prev-links");
        if (!el) {
          return "skip";
        }
        return window.getComputedStyle(el).display === "none" ? "pass" : "fail";
      }));
      add("Issue changesets/history ordering", await page.evaluate(() => {
        const changesets = document.querySelector("#issue-changesets");
        const history = document.querySelector("#history");
        if (!changesets || !history) {
          return "skip";
        }
        return (changesets.compareDocumentPosition(history) & Node.DOCUMENT_POSITION_FOLLOWING) ? "pass" : "fail";
      }));
      await screenshot("audit-issue-page.png");

      const issueIdMatch = firstIssueHref.match(/\/issues\/(\d+)/);
      const issueId = issueIdMatch && issueIdMatch[1];
      if (issueId) {
        await goto(`${baseUrl}/issues/${issueId}/time_entries/new`);
        const backUrl = await page.locator('input[name="back_url"]').getAttribute("value").catch(() => null);
        add("Time entry back_url override", backUrl === `/issues/${issueId}` ? "pass" : "fail", {
          backUrl,
          issueId
        });
        add("Payment Reference ID UI present", (await page.locator("#time_entry_custom_field_values_36").count().catch(() => 0)) ? "pass" : "skip");
        await screenshot("audit-time-entry-new.png");
      } else {
        add("Time entry back_url override", "skip", { reason: "No issue id" });
        add("Payment Reference ID UI present", "skip", { reason: "No issue id" });
      }
    } else {
      add("Hide issue next/previous links", "skip", { reason: "No issue found" });
      add("Issue changesets/history ordering", "skip", { reason: "No issue found" });
      add("Time entry back_url override", "skip", { reason: "No issue found" });
      add("Payment Reference ID UI present", "skip", { reason: "No issue found" });
    }

    const reportPath = path.join(outDir, "theme-backport-audit.json");
    fs.writeFileSync(reportPath, JSON.stringify(results, null, 2));
    console.log(JSON.stringify(results, null, 2));

    const failures = results.filter((result) => requiredChecks.has(result.name) && result.status !== "pass");
    await browser.close();

    if (failures.length) {
      console.error(`Required backport checks failed: ${failures.map((item) => item.name).join(", ")}`);
      process.exit(1);
    }
  } catch (error) {
    fs.writeFileSync(path.join(outDir, "theme-backport-audit-error.txt"), String(error.stack || error));
    await browser.close();
    throw error;
  }
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exit(1);
});
