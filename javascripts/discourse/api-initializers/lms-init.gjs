import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";

export default apiInitializer((api) => {
  var siteSettings = api.container.lookup("service:site-settings");
  if (!siteSettings.lms_enabled) return;

  function getCategoryById(categoryId) {
    if (!categoryId) return null;
    var site = api.container.lookup("service:site");
    return site.categories?.find(function(c) { return c.id === categoryId; }) || null;
  }

  function isLmsCategory(categoryId) {
    var cat = getCategoryById(categoryId);
    if (!cat) return false;
    if (cat.lms_enabled === true || cat.lms_enabled === "true") return true;
    if (cat.custom_fields?.lms_enabled === true || cat.custom_fields?.lms_enabled === "true") return true;
    return false;
  }

  function getCategoryIdFromUrl(url) {
    var pathParts = url.replace(/^\/c\//, "").split("/");
    return parseInt(pathParts[pathParts.length - 1], 10) || 0;
  }

  // --- 1. Completion Button on first post ---
  api.decorateCookedElement(
    function(element, helper) {
      if (!helper) return;
      if (element.closest(".d-editor-preview, .composer-popup, .edit-body")) return;

      var post = helper.getModel();
      if (!post || post.post_number !== 1) return;

      var topic = post.topic;
      if (!topic) return;
      if (!api.getCurrentUser()) return;
      if (!isLmsCategory(topic.category_id)) return;
      if (element.querySelector(".lms-completion-wrapper")) return;

      var wrapper = document.createElement("div");
      wrapper.className = "lms-completion-wrapper";

      var btn = document.createElement("button");
      btn.className = "btn btn-primary lms-complete-btn";
      btn.innerHTML = '<svg class="lms-check-icon" width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg><span class="lms-btn-text">Laden...</span>';
      btn.disabled = true;

      var nextContainer = document.createElement("div");
      nextContainer.className = "lms-next-lesson";

      wrapper.appendChild(btn);
      wrapper.appendChild(nextContainer);
      element.appendChild(wrapper);

      ajax("/lms/status/" + topic.id + ".json")
        .then(function(result) {
          btn.disabled = false;
          setButtonState(btn, result.completed, result.needs_review);
          if (result.completed) {
            loadNextLesson(topic.category_id, topic.id, nextContainer);
          }
        })
        .catch(function() {
          btn.disabled = false;
          setButtonState(btn, false, false);
        });

      btn.addEventListener("click", function() {
        btn.disabled = true;
        ajax("/lms/complete/" + topic.id, { type: "POST" })
          .then(function(result) {
            btn.disabled = false;
            setButtonState(btn, result.completed, result.needs_review);
            if (result.completed) {
              loadNextLesson(topic.category_id, topic.id, nextContainer);
              if (result.certificate) {
                showCertificateModal(result.certificate);
              }
            } else {
              nextContainer.innerHTML = "";
            }
          })
          .catch(function() { btn.disabled = false; });
      });
    },
    { id: "discourse-lms-completion" }
  );

  function setButtonState(btn, completed, needsReview) {
    var textEl = btn.querySelector(".lms-btn-text");
    if (completed) {
      btn.classList.remove("btn-primary");
      btn.classList.add("btn-default", "lms-done");
      textEl.textContent = "Abschluss aufheben";
    } else {
      btn.classList.remove("btn-default", "lms-done");
      btn.classList.add("btn-primary");
      textEl.textContent = "Als abgeschlossen markieren";
    }
    if (needsReview) {
      btn.classList.add("lms-needs-review");
      textEl.textContent = "Aktualisiert \u2014 bitte erneut ansehen";
    } else {
      btn.classList.remove("lms-needs-review");
    }
  }

  function loadNextLesson(categoryId, currentTopicId, container) {
    ajax("/lms/lessons/" + categoryId + ".json")
      .then(function(data) {
        var lessons = data.lessons || [];
        var currentIdx = -1;
        for (var i = 0; i < lessons.length; i++) {
          if (lessons[i].id === currentTopicId) { currentIdx = i; break; }
        }
        if (currentIdx >= 0 && currentIdx < lessons.length - 1) {
          var next = lessons[currentIdx + 1];
          container.innerHTML = '<a href="/t/' + next.slug + '/' + next.id + '" class="btn btn-default lms-next-btn"><svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" style="margin-right:0.4em;vertical-align:middle"><path d="M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z"/></svg>Weiter zu: ' + next.title + '</a>';
        }
      })
      .catch(function() {});
  }

  // --- Certificate helpers ---

  function escapeXml(str) {
    return String(str == null ? "" : str).replace(/[<>&"']/g, function(c) {
      return ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;", "'": "&apos;" })[c];
    });
  }

  function formatCertDate(iso) {
    if (!iso) return "";
    try {
      var d = new Date(iso);
      var locale = (document.documentElement.lang || "de").replace(/_/g, "-");
      return d.toLocaleDateString(locale, { year: "numeric", month: "long", day: "numeric" });
    } catch (e) {
      return iso;
    }
  }

  // Build a pseudo-random dot/X grid inside a rectangle. Each cell's mark
  // is decided by a deterministic hash of its (x, y) plus a seed, so the
  // distribution looks chaotic but reproduces the same way every render.
  function buildDotXGrid(opts) {
    var elems = [];
    for (var py = opts.y0; py <= opts.y1; py += opts.step) {
      for (var px = opts.x0; px <= opts.x1; px += opts.step) {
        var hash = ((px + 1) * 73 + (py + 1) * 137 + opts.seed * 19) % 100;
        if (hash < opts.xRatio) {
          var s = 1.6;
          elems.push(
            '<path d="M' + (px - s) + ' ' + (py - s) + 'l' + (s * 2) + ' ' + (s * 2) +
            'M' + (px - s) + ' ' + (py + s) + 'l' + (s * 2) + ' ' + (-s * 2) +
            '" stroke="' + opts.color + '" stroke-opacity="' + opts.xOpacity +
            '" stroke-width="0.5" stroke-linecap="round" fill="none"/>'
          );
        } else {
          elems.push(
            '<circle cx="' + px + '" cy="' + py + '" r="1.05" fill="' + opts.color +
            '" fill-opacity="' + opts.dotOpacity + '"/>'
          );
        }
      }
    }
    return elems.join("");
  }

  function renderCertificateSvg(cert) {
    var name = escapeXml((cert.display_name || "").toUpperCase());
    var category = escapeXml(cert.category_name || "");
    var date = escapeXml(formatCertDate(cert.issued_at));
    var certId = escapeXml(cert.cert_id || "");

    // Dynamic letter-spacing / font-size for the name so long names don't
    // overflow the printable area.
    var rawName = cert.display_name || "";
    var nameSpacing = rawName.length > 22 ? 4 : (rawName.length > 16 ? 7 : 10);
    var nameSize = rawName.length > 28 ? 42 : (rawName.length > 20 ? 50 : 56);

    // Unique SVG def IDs per cert, in case multiple certs render on one page
    // later (e.g. a profile tab listing all certs).
    var uid = "c-" + String(cert.cert_id || "x").replace(/[^a-z0-9]/gi, "").slice(0, 10);
    var gOx = "oxGrad-" + uid;
    var gGlow = "oxGlow-" + uid;
    var gFadeTop = "oxFadeTop-" + uid;
    var gFadeBot = "oxFadeBot-" + uid;
    var mTop = "maskTop-" + uid;
    var mBot = "maskBot-" + uid;

    return [
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1188 840" preserveAspectRatio="xMidYMid meet" font-family="\'Inter\',\'Helvetica Neue\',Arial,sans-serif">',

        // === Defs ===
        '<defs>',
          '<linearGradient id="', gOx, '" x1="0%" y1="0%" x2="100%" y2="100%">',
            '<stop offset="0%" stop-color="#6d8cff"/>',
            '<stop offset="50%" stop-color="#a78bfa"/>',
            '<stop offset="100%" stop-color="#6d8cff"/>',
          '</linearGradient>',
          '<radialGradient id="', gGlow, '" cx="50%" cy="50%" r="65%">',
            '<stop offset="0%" stop-color="#6d8cff" stop-opacity="0.22"/>',
            '<stop offset="45%" stop-color="#a78bfa" stop-opacity="0.08"/>',
            '<stop offset="75%" stop-color="#a78bfa" stop-opacity="0"/>',
          '</radialGradient>',
          '<radialGradient id="', gFadeTop, '" cx="594" cy="215" r="320" gradientUnits="userSpaceOnUse">',
            '<stop offset="0%" stop-color="black" stop-opacity="1"/>',
            '<stop offset="55%" stop-color="black" stop-opacity="0.5"/>',
            '<stop offset="100%" stop-color="black" stop-opacity="0"/>',
          '</radialGradient>',
          '<radialGradient id="', gFadeBot, '" cx="594" cy="600" r="360" gradientUnits="userSpaceOnUse">',
            '<stop offset="0%" stop-color="black" stop-opacity="1"/>',
            '<stop offset="55%" stop-color="black" stop-opacity="0.5"/>',
            '<stop offset="100%" stop-color="black" stop-opacity="0"/>',
          '</radialGradient>',
          '<mask id="', mTop, '" maskUnits="userSpaceOnUse">',
            '<rect x="0" y="0" width="1188" height="430" fill="white"/>',
            '<rect x="0" y="0" width="1188" height="430" fill="url(#', gFadeTop, ')"/>',
          '</mask>',
          '<mask id="', mBot, '" maskUnits="userSpaceOnUse">',
            '<rect x="0" y="432" width="1188" height="408" fill="white"/>',
            '<rect x="0" y="432" width="1188" height="408" fill="url(#', gFadeBot, ')"/>',
          '</mask>',
        '</defs>',

        // === Top half (black + chaotic white dot/X grid + glow) ===
        '<rect width="1188" height="430" fill="#0f1216"/>',
        '<g mask="url(#', mTop, ')">',
          buildDotXGrid({ x0: 14, x1: 1174, y0: 14, y1: 416, step: 28, color: "#ffffff", dotOpacity: 0.14, xOpacity: 0.34, xRatio: 10, seed: 1 }),
        '</g>',
        '<rect width="1188" height="430" fill="url(#', gGlow, ')"/>',

        // Wordmark "OX CAMPUS" — gradient fill
        '<text x="594" y="200" text-anchor="middle" font-size="68" font-weight="800" fill="url(#', gOx, ')" letter-spacing="14">OX CAMPUS</text>',
        // Thin gradient underline divider
        '<line x1="494" y1="240" x2="694" y2="240" stroke="url(#', gOx, ')" stroke-opacity="0.5" stroke-width="1"/>',
        // Subtitle with wide tracking
        '<text x="594" y="295" text-anchor="middle" font-size="16" letter-spacing="8" fill="#ffffff" font-weight="400">TEILNAHMEBEST&#196;TIGUNG VON</text>',

        // === Gradient divider strip between halves ===
        '<rect x="0" y="428" width="1188" height="4" fill="url(#', gOx, ')"/>',

        // === Bottom half (white + chaotic blue dot/X grid) ===
        '<rect x="0" y="432" width="1188" height="408" fill="#ffffff"/>',
        '<g mask="url(#', mBot, ')">',
          buildDotXGrid({ x0: 14, x1: 1174, y0: 446, y1: 824, step: 28, color: "#6d8cff", dotOpacity: 0.22, xOpacity: 0.50, xRatio: 10, seed: 7 }),
        '</g>',

        // Name — solid black for dignity / contrast
        '<text x="594" y="555" text-anchor="middle" font-size="', nameSize, '" font-weight="700" fill="#1a1a1a" letter-spacing="', nameSpacing, '">', name, '</text>',
        // Subtle gradient separator under the name
        '<line x1="494" y1="595" x2="694" y2="595" stroke="url(#', gOx, ')" stroke-opacity="0.45" stroke-width="1.2"/>',
        // Body text — multi-line
        '<text x="594" y="650" text-anchor="middle" font-size="18" fill="#3a3a3a">',
          'Der Online-Kurs ',
          '<tspan font-weight="700" fill="#1a1a1a">', category, '</tspan>',
        '</text>',
        '<text x="594" y="678" text-anchor="middle" font-size="18" fill="#3a3a3a">',
          'wurde am ',
          '<tspan font-weight="700" fill="#1a1a1a">', date, '</tspan>',
          ' auf dem OX Campus erfolgreich abgeschlossen.',
        '</text>',

        // Cert-ID, bottom-left
        '<text x="80" y="810" font-size="9" fill="#9a9a9a" font-family="monospace" letter-spacing="0.5">ID &#183; ', certId, '</text>',
        // Footer impressum, bottom-right
        '<text x="1108" y="810" text-anchor="end" font-size="9" fill="#9a9a9a" letter-spacing="0.5">Out Of The Box Science GmbH &#183; Bunsenstra&#223;e 43 &#183; 50997 K&#246;ln &#183; www.outoftheb-ox.de</text>',

      '</svg>'
    ].join("");
  }

  function downloadCertificate(cert) {
    var svg = renderCertificateSvg(cert);
    var title = escapeXml("Zertifikat – " + (cert.category_name || ""));
    var html = [
      '<!DOCTYPE html>',
      '<html lang="de"><head>',
      '<meta charset="utf-8" />',
      '<title>', title, '</title>',
      '<link rel="preconnect" href="https://fonts.googleapis.com">',
      '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>',
      '<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">',
      '<style>',
      '@page { size: A4 landscape; margin: 0; }',
      'html, body { margin: 0; padding: 0; background: #0f1216; }',
      '.cert-wrap { display: flex; align-items: center; justify-content: center; min-height: 100vh; }',
      'svg { width: 100%; max-width: 297mm; height: auto; display: block; box-shadow: 0 12px 40px rgba(0,0,0,0.5); }',
      '@media print {',
      '  html, body { background: white !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }',
      '  .cert-wrap { min-height: auto; }',
      '  svg { width: 297mm; height: 210mm; box-shadow: none; }',
      '}',
      '</style></head><body>',
      '<div class="cert-wrap">', svg, '</div>',
      '<script>window.addEventListener("load",function(){setTimeout(function(){window.print();},400);});</script>',
      '</body></html>'
    ].join("");

    var w = window.open("", "_blank");
    if (!w) {
      alert("Bitte erlaube Popups, damit das Zertifikat geöffnet werden kann.");
      return;
    }
    w.document.open();
    w.document.write(html);
    w.document.close();
  }

  function showCertificateModal(cert) {
    if (document.querySelector(".lms-cert-modal-overlay")) return;

    var overlay = document.createElement("div");
    overlay.className = "lms-cert-modal-overlay";

    var modal = document.createElement("div");
    modal.className = "lms-cert-modal";
    modal.innerHTML = [
      '<div class="lms-cert-modal-icon">',
      '<svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="7"/><polyline points="8.21 13.89 7 23 12 20 17 23 15.79 13.88"/></svg>',
      '</div>',
      '<h2 class="lms-cert-modal-title">Glückwunsch!</h2>',
      '<p class="lms-cert-modal-subtitle">Du hast <strong>', escapeXml(cert.category_name), '</strong> abgeschlossen.</p>',
      '<label class="lms-cert-modal-label">Name auf dem Zertifikat',
      '<input type="text" class="lms-cert-name-input" maxlength="120" />',
      '</label>',
      '<p class="lms-cert-modal-hint">Standard ist dein Anzeigename. Du kannst es jederzeit ändern.</p>',
      '<div class="lms-cert-modal-actions">',
      '<button class="btn btn-flat lms-cert-cancel">Später</button>',
      '<button class="btn btn-primary lms-cert-download">Zertifikat herunterladen</button>',
      '</div>'
    ].join("");

    // Set name via property to avoid HTML-injection through the value attribute
    var nameInput = modal.querySelector(".lms-cert-name-input");
    nameInput.value = cert.display_name || "";

    overlay.appendChild(modal);
    document.body.appendChild(overlay);

    function close() {
      if (overlay.parentNode) overlay.parentNode.removeChild(overlay);
    }

    modal.querySelector(".lms-cert-cancel").addEventListener("click", close);
    overlay.addEventListener("click", function(e) {
      if (e.target === overlay) close();
    });
    document.addEventListener("keydown", function escHandler(e) {
      if (e.key === "Escape") {
        close();
        document.removeEventListener("keydown", escHandler);
      }
    });

    var downloadBtn = modal.querySelector(".lms-cert-download");
    downloadBtn.addEventListener("click", function() {
      var newName = (nameInput.value || "").trim();
      if (!newName) {
        nameInput.focus();
        return;
      }
      downloadBtn.disabled = true;
      downloadBtn.textContent = "Speichern…";

      ajax("/lms/certificate/" + cert.category_id, {
        type: "PUT",
        data: { display_name: newName }
      })
        .then(function(result) {
          close();
          downloadCertificate(result.certificate || Object.assign({}, cert, { display_name: newName }));
        })
        .catch(function() {
          downloadBtn.disabled = false;
          downloadBtn.textContent = "Zertifikat herunterladen";
        });
    });

    setTimeout(function() {
      nameInput.focus();
      nameInput.select();
    }, 50);
  }

  // Look up the user's certificate for this category (if any) and render
  // a "Zertifikat herunterladen" action next to the progress bar. Idempotent:
  // bails out if an action already exists for this header.
  function maybeAddCertificateAction(categoryId, courseHeader) {
    if (!courseHeader) return;
    if (courseHeader.querySelector(".lms-cert-action")) return;

    ajax("/lms/certificates.json")
      .then(function(data) {
        var certs = (data && data.certificates) || [];
        var match = null;
        for (var i = 0; i < certs.length; i++) {
          if (certs[i].category_id === categoryId) { match = certs[i]; break; }
        }
        if (!match) return;

        var wrap = document.createElement("div");
        wrap.className = "lms-cert-action";
        if (match.status === "outdated") wrap.classList.add("is-outdated");

        var label = document.createElement("span");
        label.className = "lms-cert-action-label";
        if (match.status === "outdated") {
          label.textContent = "Dein Zertifikat ist veraltet — eine Lektion wurde aktualisiert.";
        } else {
          label.textContent = "Dein Zertifikat ist verfügbar.";
        }

        var btn = document.createElement("button");
        btn.className = "btn btn-default lms-cert-redownload";
        btn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" style="margin-right:0.4em;vertical-align:middle"><path d="M19 9h-4V3H9v6H5l7 7 7-7zM5 18v2h14v-2H5z"/></svg><span>Zertifikat herunterladen</span>';
        btn.addEventListener("click", function() {
          downloadCertificate(match);
        });

        wrap.appendChild(label);
        wrap.appendChild(btn);
        courseHeader.appendChild(wrap);
      })
      .catch(function() { /* silent */ });
  }

  // --- 2. Category Page: Course header + topic badges ---
  api.onPageChange(function(url) {
    // Clean up old LMS elements from previous category page
    document.querySelectorAll(".lms-course-header, .lms-progress-bar, .lms-cert-action").forEach(function(el) { el.remove(); });
    document.querySelectorAll(".lms-position, .lms-position-input, .lms-status-badge").forEach(function(el) { el.remove(); });

    if (!url.match(/^\/c\//)) return;

    var categoryId = getCategoryIdFromUrl(url);
    if (!categoryId) return;

    // Wait for the category title element to exist instead of a fixed 600ms
    // delay. requestAnimationFrame polls once per paint (~16ms), so the
    // header appears on the first frame it can — no visible layout shift.
    var framesLeft = 40; // ~640ms hard cap on slow devices
    function waitForTitle() {
      var titleReady = document.querySelector(".category-title-contents .category-name, .category-heading");
      if (!titleReady && framesLeft-- > 0) {
        requestAnimationFrame(waitForTitle);
        return;
      }
      runLmsHeader();
    }
    requestAnimationFrame(waitForTitle);

    function runLmsHeader() {
      var currentUser = api.getCurrentUser();
      var isAdmin = currentUser && currentUser.admin;
      var isLms = isLmsCategory(categoryId);

      // Read current sort order from category data
      var cat = getCategoryById(categoryId);
      var sortOrder = cat?.lms_sort_order || cat?.custom_fields?.lms_sort_order || "created";

      var titleEl = document.querySelector(".category-title-contents .category-name, .category-heading");
      if (titleEl && !document.querySelector(".lms-course-header")) {
        var header = document.createElement("div");
        header.className = "lms-course-header";

        if (isAdmin) {
          // Kurs checkbox
          var label = document.createElement("label");
          label.className = "lms-admin-toggle";
          label.title = isLms ? "Kurs-Modus deaktivieren" : "Als Kurs aktivieren";

          var checkbox = document.createElement("input");
          checkbox.type = "checkbox";
          checkbox.checked = isLms;
          checkbox.className = "lms-admin-checkbox";

          var labelText = document.createElement("span");
          labelText.className = "lms-admin-label";
          labelText.textContent = "Kurs";

          label.appendChild(checkbox);
          label.appendChild(labelText);
          header.appendChild(label);

          checkbox.addEventListener("change", function() {
            checkbox.disabled = true;
            var newState = checkbox.checked;

            ajax("/categories/" + categoryId + ".json", {
              type: "PUT",
              data: { "custom_fields[lms_enabled]": newState }
            })
              .then(function() {
                var cat = getCategoryById(categoryId);
                if (cat) {
                  if (!cat.custom_fields) cat.custom_fields = {};
                  cat.custom_fields.lms_enabled = newState;
                }
                checkbox.disabled = false;
                label.title = newState ? "Kurs-Modus deaktivieren" : "Als Kurs aktivieren";
                window.location.reload();
              })
              .catch(function() {
                checkbox.checked = !newState;
                checkbox.disabled = false;
              });
          });

          // Sort order dropdown (only visible when Kurs is active)
          if (isLms) {
            var sortWrapper = document.createElement("div");
            sortWrapper.className = "lms-sort-wrapper";

            var sortLabel = document.createElement("span");
            sortLabel.className = "lms-sort-label";
            sortLabel.textContent = "Sortierung:";
            sortWrapper.appendChild(sortLabel);

            var select = document.createElement("select");
            select.className = "lms-sort-select";
            var options = [
              { value: "created", text: "Erstelldatum" },
              { value: "title", text: "Titel (A-Z)" },
              { value: "manual", text: "Manuell" }
            ];
            options.forEach(function(opt) {
              var option = document.createElement("option");
              option.value = opt.value;
              option.textContent = opt.text;
              if (opt.value === sortOrder) option.selected = true;
              select.appendChild(option);
            });
            sortWrapper.appendChild(select);
            header.appendChild(sortWrapper);

            select.addEventListener("change", function() {
              select.disabled = true;
              ajax("/categories/" + categoryId + ".json", {
                type: "PUT",
                data: { "custom_fields[lms_sort_order]": select.value }
              })
                .then(function() {
                  var cat = getCategoryById(categoryId);
                  if (cat) {
                    if (!cat.custom_fields) cat.custom_fields = {};
                    cat.custom_fields.lms_sort_order = select.value;
                    cat.lms_sort_order = select.value;
                  }
                  window.location.reload();
                })
                .catch(function() {
                  select.disabled = false;
                });
            });
          }
        } else {
          if (isLms) {
            var courseBadge = document.createElement("span");
            courseBadge.className = "lms-course-badge";
            courseBadge.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" style="vertical-align:middle;margin-right:0.3em"><path d="M5 13.18v4L12 21l7-3.82v-4L12 17l-7-3.82zM12 3L1 9l11 6 9-4.91V17h2V9L12 3z"/></svg>Kurs';
            header.appendChild(courseBadge);
          }
        }

        titleEl.after(header);
      }

      if (!isLms) return;

      // Progress bar — insert a skeleton with 0% fill immediately so the
      // space is reserved and layout doesn't jump when the ajax response
      // arrives. We then update the existing element in place.
      var courseHeader = document.querySelector(".lms-course-header");
      if (courseHeader && !document.querySelector(".lms-progress-bar") && currentUser) {
        var progressEl = document.createElement("div");
        progressEl.className = "lms-progress-bar lms-progress-loading";
        progressEl.innerHTML = '<div class="lms-progress-track"><div class="lms-progress-fill" style="width:0%"></div></div><span class="lms-progress-label">&nbsp;</span>';
        courseHeader.appendChild(progressEl);

        ajax("/lms/progress/" + categoryId + ".json")
          .then(function(data) {
            progressEl.classList.remove("lms-progress-loading");
            var pct = data.percent || 0;
            var fill = progressEl.querySelector(".lms-progress-fill");
            var label = progressEl.querySelector(".lms-progress-label");
            if (fill) fill.style.width = pct + "%";
            if (label) label.textContent = data.completed + " von " + data.total + " Lektionen abgeschlossen";
            // Surface a re-download button once the user has any cert for
            // this category (either freshly active or outdated).
            maybeAddCertificateAction(categoryId, courseHeader);
          })
          .catch(function() {
            // Leave the skeleton as-is; better than flashing an error.
            progressEl.classList.remove("lms-progress-loading");
          });
      }

      // Topic list: reorder DOM rows to match LMS sort, then add badges and auto-numbering
      if (currentUser) {
        ajax("/lms/lessons/" + categoryId + ".json")
          .then(function(data) {
            var lessons = data.lessons || [];

            // Build ordered topic ID list and lookup maps
            var orderedIds = lessons.map(function(l) { return l.id; });
            var byId = {};
            for (var i = 0; i < lessons.length; i++) {
              byId[lessons[i].id] = lessons[i];
            }

            // Build auto-number map: sequential display numbers, skip "Über" topics
            var displayNum = {};
            var counter = 1;
            for (var i = 0; i < lessons.length; i++) {
              var isAboutTopic = /^[Üü]ber die Kategorie/i.test(lessons[i].title);
              if (!isAboutTopic) {
                displayNum[lessons[i].id] = counter;
                counter++;
              }
            }

            // Collect topic rows (order is already correct — server sorts them
            // for LMS categories via TopicQuery#apply_ordering). We only need
            // the row lookup here to attach numbers/badges below.
            var rows = document.querySelectorAll("tr.topic-list-item, .topic-list-item");
            var rowById = {};
            rows.forEach(function(row) {
              var link = row.querySelector("a.title.raw-link, a.raw-topic-link");
              if (!link) return;
              var href = link.getAttribute("href") || "";
              var match = href.match(/\/t\/[^/]+\/(\d+)/);
              if (!match) return;
              rowById[parseInt(match[1], 10)] = row;
            });

            // Helper: save positions to server and reload
            function savePositions(orderedTopicIds) {
              var positions = {};
              orderedTopicIds.forEach(function(id, idx) {
                positions[id] = idx + 1;
              });
              ajax("/lms/reorder/" + categoryId, {
                type: "PUT",
                data: { positions: positions }
              }).then(function() {
                window.location.reload();
              });
            }

            // Helper: move a topic to a specific position
            function moveToPosition(topicId, newPos) {
              newPos = Math.max(1, Math.min(orderedIds.length, newPos));
              var oldIdx = orderedIds.indexOf(topicId);
              if (oldIdx < 0) return;
              // Remove from old position
              orderedIds.splice(oldIdx, 1);
              // Insert at new position (1-based → 0-based)
              orderedIds.splice(newPos - 1, 0, topicId);
              savePositions(orderedIds);
            }

            // Now add numbering, badges, and position inputs to the reordered rows
            Object.keys(rowById).forEach(function(topicIdStr) {
              var topicId = parseInt(topicIdStr, 10);
              var row = rowById[topicId];
              var lesson = byId[topicId];
              if (!row || !lesson) return;

              var link = row.querySelector("a.title.raw-link, a.raw-topic-link");
              if (!link) return;

              // Auto-numbering: show display number unless title already starts with a number
              var num = displayNum[topicId];
              if (num && !row.querySelector(".lms-position") && !row.querySelector(".lms-position-input")) {
                var titleStartsWithNumber = /^\d/.test(lesson.title);
                if (!titleStartsWithNumber) {
                  // Admin + manual sort → editable number input
                  if (isAdmin && sortOrder === "manual") {
                    var input = document.createElement("input");
                    input.type = "number";
                    input.className = "lms-position-input";
                    input.value = num;
                    input.min = 1;
                    input.max = orderedIds.length;
                    input.title = "Position eingeben + Enter";
                    input.addEventListener("keydown", function(e) {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        var newPos = parseInt(input.value, 10);
                        if (newPos && newPos !== num) {
                          input.disabled = true;
                          moveToPosition(topicId, newPos);
                        }
                      }
                    });
                    input.addEventListener("blur", function() {
                      var newPos = parseInt(input.value, 10);
                      if (newPos && newPos !== num) {
                        input.disabled = true;
                        moveToPosition(topicId, newPos);
                      }
                    });
                    link.parentNode.insertBefore(input, link);
                  } else {
                    // Normal display number
                    var posEl = document.createElement("span");
                    posEl.className = "lms-position";
                    posEl.textContent = num + ". ";
                    link.prepend(posEl);
                  }
                }
              }

              if (!row.querySelector(".lms-status-badge")) {
                if (lesson.needs_review) {
                  var badge = document.createElement("span");
                  badge.className = "lms-status-badge lms-review";
                  badge.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg> Aktualisiert';
                  link.after(badge);
                } else if (lesson.completed) {
                  var badge = document.createElement("span");
                  badge.className = "lms-status-badge lms-done";
                  badge.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/></svg> Abgeschlossen';
                  link.after(badge);
                }
              }
            });
          })
          .catch(function() {});
      }
    }
  });

});
