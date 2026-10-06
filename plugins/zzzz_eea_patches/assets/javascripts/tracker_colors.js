/* Server-rendered rules cover initial HTML. Also support trackers created
   while a board is open, whose cards arrive via AJAX or ActionCable. */
(function () {
  "use strict";
  const prefix = "taskman-tracker-color-";
  const selector = '[class*="' + prefix + '"]';

  function start() {
    const style = document.getElementById("taskman-tracker-colors");
    if (!style || !style.sheet) return;
    const known = new Set(Array.from(style.textContent.matchAll(/taskman-tracker-color-([0-9a-f]{6})/g), match => match[1]));

    function rgb(hex) {
      return hex.match(/../g).map(channel => parseInt(channel, 16));
    }

    function mix(hex, target, weight) {
      return rgb(hex).map(channel => Math.round(channel * (1 - weight) + target * weight).toString(16).padStart(2, "0")).join("");
    }

    function foreground(hex) {
      const linear = rgb(hex).map(channel => {
        const value = channel / 255;
        return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
      });
      return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722 > 0.179 ? "#000000" : "#ffffff";
    }

    function addRules(element) {
      if (element.nodeType !== 1) return;
      for (const token of element.classList) {
        const match = /^taskman-tracker-color-([0-9a-f]{6})$/.exec(token);
        if (!match || known.has(match[1])) continue;
        const hex = match[1];
        const hover = mix(hex, 0, 0.2);
        style.sheet.insertRule("." + prefix + hex + " {" +
          "--taskman-tracker-color:#" + hex + ";" +
          "--taskman-tracker-text:" + foreground(hex) + ";" +
          "--taskman-tracker-hover:#" + hover + ";" +
          "--taskman-tracker-hover-text:" + foreground(hover) + ";" +
          "--taskman-tracker-tint:#" + mix(hex, 255, 0.85) + ";}", style.sheet.cssRules.length);
        known.add(hex);
      }
    }

    function scan(element) {
      if (element.nodeType !== 1) return;
      addRules(element);
      element.querySelectorAll(selector).forEach(addRules);
    }

    scan(document.body);
    new MutationObserver(records => {
      for (const record of records) {
        if (record.type === "attributes") addRules(record.target);
        else record.addedNodes.forEach(scan);
      }
    }).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
}());
