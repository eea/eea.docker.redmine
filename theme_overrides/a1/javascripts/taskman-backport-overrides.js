/* Taskman backports for A1 theme (kept isolated from upstream A1 assets). */
(function () {
  "use strict";

  function onReady(cb) {
    if (window.jQuery) {
      window.jQuery(cb);
      return;
    }
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", cb, { once: true });
      return;
    }
    cb();
  }

  function getSiteUrl() {
    return window.location.origin;
  }

  function getCurrentUserLink($) {
    var $loggedIn = $("#loggedas");
    if (!$loggedIn.length) {
      return null;
    }
    return $loggedIn.find(".user").first();
  }

  function getUserToken($) {
    var dfd = $.Deferred();
    var $user = getCurrentUserLink($);
    var match;
    var userId;
    var keyName;
    var cached;

    if (!$user || !$user.length) {
      return dfd.reject("not-logged-in");
    }

    match = ($user.attr("href") || "").match(/\d+/);
    if (!match) {
      return dfd.reject("missing-user-id");
    }

    userId = parseInt(match[0], 10);
    keyName = "t_logged_user_api_key_" + userId;
    cached = window.sessionStorage && window.sessionStorage.getItem(keyName);
    if (cached) {
      return dfd.resolve({ api_key: cached, user_id: userId });
    }

    $.get(getSiteUrl() + "/my/api_key").done(function (res) {
      var $res = $(res);
      var apiKey = $res.find("pre").text();
      if (window.sessionStorage && apiKey) {
        window.sessionStorage.setItem(keyName, apiKey);
      }
      dfd.resolve({ api_key: apiKey, user_id: userId });
    }).fail(function () {
      dfd.reject("failed-api-key");
    });

    return dfd.promise();
  }

  onReady(function () {
    var $ = window.jQuery;
    if (!$) {
      return;
    }

    function forceTaskmanFavicon() {
      // Keep favicon local to the deployed app; no external fetch at runtime.
      var faviconUrl = "/favicon.ico?v=taskman-local";
      var selectors = "link[rel='icon'], link[rel='shortcut icon']";
      var links = document.querySelectorAll(selectors);

      if (!links.length) {
        var link = document.createElement("link");
        link.setAttribute("rel", "icon");
        link.setAttribute("type", "image/x-icon");
        link.setAttribute("href", faviconUrl);
        document.head.appendChild(link);
        return;
      }

      links.forEach(function (linkEl) {
        linkEl.setAttribute("href", faviconUrl);
      });
    }

    function moveProjectsBoxAboveMembers() {
      $(".members.box").next().filter(".projects.box").insertBefore(".members.box");
    }

    forceTaskmanFavicon();
    // #106078 block search for anonymous
    function blockSearchAnonymous() {
      if (!$("#loggedas").length) {
        $("#quick-search form").hide();
        $("#quick-search, .quick-search").hide();
        $("input[placeholder='Search'], input[placeholder='search']")
          .closest("form, #quick-search, .quick-search, .search-box")
          .hide();
        document.cookie = "_redmine_eea=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;";
      } else {
        var d = new Date();
        d.setTime(d.getTime() + 86400000);
        document.cookie = "_redmine_eea=1; expires=" + d.toUTCString() + ";path=/";
      }
    }

    function fixIssueHistoryOrder() {
      var length = $("#issue-changesets").nextUntil("#history").length;
      var i = 0;
      while (i < length) {
        $("#history").prev().insertAfter("#history");
        i += 1;
      }
    }

    function focusLoginAnd2fa() {
      $("#login-form #username").trigger("focus");
      $("#twofa_code").trigger("focus");
    }

    function ensureTimeEntryBackUrl() {
      if (!window.location.pathname.match(/\/time_entries\/new$/)) {
        return;
      }
      var issuePathMatch = window.location.pathname.match(/\/issues\/(\d+)\/time_entries\/new$/);
      var issueId = (issuePathMatch && issuePathMatch[1]) || $("#time_entry_issue_id").val();
      if (!issueId) {
        return;
      }
      var desiredBackUrl = "/issues/" + issueId;
      var $form = $("#new_time_entry, form.time_entry");
      if (!$form.length) {
        return;
      }
      var $backUrl = $form.find("input[name='back_url']").first();
      if (!$backUrl.length) {
        $backUrl = $("<input/>", {
          type: "hidden",
          name: "back_url"
        }).appendTo($form);
      }
      $backUrl.val(desiredBackUrl);
      $form.off("submit.taskmanBackUrl").on("submit.taskmanBackUrl", function () {
        $(this).find("input[name='back_url']").val(desiredBackUrl);
      });
    }

    function normalizeAdminWikiLinksIconClass() {
      if (!window.location.pathname.match(/^\/admin(\/|$)/)) {
        return;
      }
      $("a.wiki-links").attr("class", "icon wiki-links");
    }

    function setupPaymentReferencePrefill() {
      var $logPayment = $("#time_entry_custom_field_values_36");
      var $ticketPayment = $("#issue_custom_field_values_71");
      var ticketPaymentValue = $ticketPayment.val() || "";
      var $warning;
      var $warningValue;

      if (!$logPayment.length) {
        return;
      }

      $logPayment.parent().before($(
        "<div class='conflict hidden' id='wrong_payment'>" +
        "<strong>Different Payment Reference ID selected</strong>" +
        "<div class='conflict-details conflict-journal'>" +
        "Be aware that you are using a different <em>Payment Reference ID</em> from what was defined in the ticket: " +
        "<em id='wrong_payment_correct_value'></em>" +
        "</div></div>"
      ));

      $warning = $("#wrong_payment");
      $warningValue = $("#wrong_payment_correct_value");
      $warningValue.text(ticketPaymentValue);

      $(".contextual").find(".icon-edit, .icon-comment").on("click", function () {
        if (ticketPaymentValue) {
          $logPayment.val(ticketPaymentValue);
          $warning.addClass("hidden");
        }
      });

      if (window.location.pathname.match(/\/time_entries\/new$/)) {
        var issueNumber = $("#time_entry_issue_id").val();
        if (issueNumber) {
          getUserToken($).then(function (token) {
            return $.ajax(getSiteUrl() + "/issues/" + issueNumber + ".json", {
              headers: {
                "X-Redmine-API-Key": token.api_key,
                "Content-Type": "application/json"
              },
              dataType: "json",
              type: "GET"
            });
          }).done(function (res) {
            var fields = (res.issue && res.issue.custom_fields) || [];
            var payment = fields.filter(function (f) {
              return (f.name || "").toLowerCase().indexOf("payment") !== -1;
            })[0];
            if (!payment || !payment.value) {
              return;
            }
            ticketPaymentValue = payment.value;
            $warningValue.text(ticketPaymentValue);
            if (!$logPayment.val()) {
              $logPayment.val(ticketPaymentValue);
            }
          });
        }
      }

      $logPayment.on("change", function () {
        var value = $(this).val();
        if (!ticketPaymentValue) {
          return;
        }
        if (value && value !== ticketPaymentValue) {
          $warning.removeClass("hidden");
        } else {
          $warning.addClass("hidden");
        }
      });
    }

    function setupWipOverloadIndicator() {
      var currentUrl = window.location.href;
      var checkedUsers = {};
      var maxLimit = 4;

      function getAssignedUser(token, $el) {
        var dfd = $.Deferred();
        var $userInfo = $el || $(".assigned-to").find(".user");
        var href = $userInfo.attr("href") || "";
        var userName = $userInfo.text();
        var match = href.match(/\d+/);
        var userId;
        var cached;
        if (!match) {
          return dfd.reject();
        }
        userId = parseInt(match[0], 10);
        cached = checkedUsers[userId];
        if (cached) {
          return dfd.resolve(cached);
        }
        cached = {
          user_id: userId,
          user_name: userName,
          api_key: token.api_key
        };
        checkedUsers[userId] = cached;
        return dfd.resolve(cached);
      }

      function getAssignedUserOverloadStatus(user) {
        var dfd = $.Deferred();
        var issuesByType = { "Total ongoing issues": 0 };
        if (typeof user.is_overloaded !== "undefined") {
          return dfd.resolve(user);
        }

        $.ajax(getSiteUrl() + "/issues.json", {
          headers: {
            "X-Redmine-API-Key": user.api_key,
            "Content-Type": "application/json"
          },
          data: {
            assigned_to_id: user.user_id,
            limit: 500,
            status_id: "2|4|8|9",
            tracker_id: "1|2|4|6"
          },
          dataType: "json",
          type: "GET"
        }).done(function (res) {
          (res.issues || []).forEach(function (issue) {
            if (!issue.assigned_to || issue.assigned_to.id !== user.user_id) {
              return;
            }
            var issueStatus = issue.status && issue.status.name;
            if (!issueStatus) {
              return;
            }
            issuesByType[issueStatus] = (issuesByType[issueStatus] || 0) + 1;
          });

          issuesByType["Total ongoing issues"] = Object.keys(issuesByType).reduce(function (acc, key) {
            if (key === "Total ongoing issues") {
              return acc;
            }
            return acc + issuesByType[key];
          }, 0);

          user.is_overloaded = issuesByType["Total ongoing issues"] > maxLimit;
          user.issues = issuesByType;
          dfd.resolve(user);
        }).fail(function () {
          dfd.reject();
        });

        return dfd.promise();
      }

      function addWipUi(user, $parent) {
        var $container = $parent || $(".assigned-to .value");
        var $panel = $(
          "<div class='overloaded-user'>" +
            "<div class='overloaded-user-head'><strong>WIP-limit of max " + maxLimit + " is reached</strong></div>" +
            "<div class='overloaded-user-body'></div>" +
            "<div class='overloaded-user-footer'><p>Why we care about WIP-limits? " +
            "<a href='https://taskman.eionet.europa.eu/projects/public-docs/wiki/Taskman_FAQ#Why-do-I-have-a-stop-sign-beside-my-name' target='_blank' class='overloaded-user-link'>Get it!</a></p></div>" +
          "</div>"
        );

        Object.keys(user.issues).forEach(function (name) {
          var value = user.issues[name];
          var line = "<p class='overloaded-user-issue-category'>" + name + ": " + value + "</p>";
          if (name === "Total ongoing issues") {
            line = "<a target='_blank' class='overloaded-user-link assigned_issues_link' href='" +
              getSiteUrl() +
              "/issues?set_filter=1&sort=status,priority%3Adesc%2Cupdated_on%3Adesc" +
              "&f[]=tracker_id&op[tracker_id]==&v[tracker_id][]=2&v[tracker_id][]=1&v[tracker_id][]=4&v[tracker_id][]=6" +
              "&f[]=status_id&op[status_id]==&v[status_id][]=2&v[status_id][]=4&v[status_id][]=8&v[status_id][]=9" +
              "&f[]=assigned_to_id&op[assigned_to_id]==&v[assigned_to_id][]=" + user.user_id + "'>" +
              line + "</a>";
          }
          $panel.find(".overloaded-user-body").append(line);
        });

        $container.each(function () {
          var $target = $(this);
          var $icon = $("<span class='overloaded-user-warning' />").appendTo($target);
          if ($.fn && $.fn.dialog) {
            var $dialogContent = $panel.clone().appendTo($target).dialog({
              title: user.user_name + " is overloaded",
              width: 300,
              dialogClass: "wip-alert",
              autoOpen: false,
              position: { my: "left top", of: $icon }
            });
            $icon.on("mouseenter", function () {
              $dialogContent.dialog("open");
            });
          } else {
            $icon.attr("title", user.user_name + " is overloaded");
          }
        });
      }

      function attachWipUiForUser($user, $parent) {
        getUserToken($)
          .then(function (token) { return getAssignedUser(token, $user); })
          .then(getAssignedUserOverloadStatus)
          .then(function (user) {
            if (user.is_overloaded) {
              addWipUi(user, $parent);
            }
          });
      }

      function applyAgileBoardWipIndicators() {
        var $targets = $(
          ".issue-card p.info.assigned-user .user, " +
          ".issue-card a[href*='/users/']"
        );
        $(".issue-card .overloaded-user-warning").remove();
        $(".issue-card .overloaded-user").remove();

        $targets.each(function () {
          var $target = $(this);
          var $user = $target.is("a[href*='/users/']")
            ? $target
            : $target.find("a[href*='/users/']").first();
          if (!$user.length) {
            return;
          }
          attachWipUiForUser($user, $user.parent());
        });
      }

      $(document).off("click.taskmanWip").on("click.taskmanWip", function (e) {
        var $dialog = $(".wip-alert");
        if ($dialog.length && !$(e.target).closest(".wip-alert").length) {
          $dialog.find(".ui-dialog-content").dialog("close");
        }
      });

      if (currentUrl.indexOf("/issues") !== -1) {
        var $issueAssignedSelect = $("#issue_assigned_to_id");
        var $issueAssignedParent = $issueAssignedSelect.parent();

        $issueAssignedSelect.off("change.taskmanWip").on("change.taskmanWip", function () {
          var selected = $(this).find(":selected")[0];
          var value = selected && selected.value;
          if (!value) {
            return;
          }
          $(".overloaded-user-warning").remove();
          var $user = $("<a />", { href: "/users/" + value, text: selected.innerText });
          getUserToken($)
            .then(function (token) { return getAssignedUser(token, $user); })
            .then(getAssignedUserOverloadStatus)
            .then(function (user) {
              if (user.is_overloaded) {
                addWipUi(user, $issueAssignedParent);
              }
            });
        });

        getUserToken($)
          .then(function (token) { return getAssignedUser(token); })
          .then(getAssignedUserOverloadStatus)
          .then(function (user) {
            if (user.is_overloaded) {
              addWipUi(user);
              addWipUi(user, $issueAssignedParent);
            }
          });
      }

      // Disabled on Agile board by request.
      if (currentUrl.indexOf("/agile/board") !== -1) {
        $(document).off("ajaxComplete.taskmanWipBoard");
      }
    }

    moveProjectsBoxAboveMembers();
    blockSearchAnonymous();
    fixIssueHistoryOrder();
    focusLoginAnd2fa();
    ensureTimeEntryBackUrl();
    normalizeAdminWikiLinksIconClass();
    setupPaymentReferencePrefill();
    setupWipOverloadIndicator();
    $(document).off("turbo:load.taskmanWip").on("turbo:load.taskmanWip", function () {
      setupWipOverloadIndicator();
    });

    // Re-apply on dynamic updates where search markup can be re-rendered.
    $(document).on("ajaxComplete", function () {
      blockSearchAnonymous();
    });
  });
}());
