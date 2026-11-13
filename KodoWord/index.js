
"use strict";

/* KodoWord — document editor */

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

const STORAGE_KEY = "kodoword_documents_v3";
const CURRENT_KEY = "kodoword_current_v3";
const FONT_KEY = "kodoword_custom_fonts_v1";

const editor = $("#editor");
const page = $("#page");
const titleInput = $("#documentTitle");
const docList = $("#docList");
const saveStatus = $("#saveStatus");
const documentMenu = $("#documentMenu");
const objectMenu = $("#objectMenu");
const toast = $("#toast");

let documents = [];
let currentId = null;
let savedRange = null;
let activeDocumentMenuId = null;
let selectedObject = null;
let saveTimer = null;
let toastTimer = null;
let pressTimer = null;
let pressOrigin = null;
let draggedObject = null;
let objectZIndex = 1;
let pageConfig = { size: "a4", orientation: "portrait", margin: 20 };

const makeId = () =>
  "doc_" + Date.now().toString(36) + "_" + Math.random().toString(36).slice(2, 8);

function showToast(message) {
  toast.textContent = message;
  toast.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove("show"), 2500);
}

function setSaveStatus(message) {
  saveStatus.textContent = message;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, ch => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;",
    '"': "&quot;", "'": "&#39;"
  })[ch]);
}

function safeJsonParse(value, fallback) {
  try {
    return JSON.parse(value) ?? fallback;
  } catch {
    return fallback;
  }
}

function loadDocuments() {
  const stored = safeJsonParse(localStorage.getItem(STORAGE_KEY), []);
  documents = Array.isArray(stored) ? stored : [];

  documents = documents.filter(d =>
    d && typeof d.id === "string" && typeof d.title === "string"
  );

  // Replace only the original starter template; preserve all user-authored content.
  documents.forEach(d => {
    if (d && typeof d.content === "string" && /Welcome to KodoWord|Your document starts here/.test(d.content)) {
      d.content = "<h1>KodoWord</h1><p>Document Editor</p>";
    }
  });

  currentId = localStorage.getItem(CURRENT_KEY);

  if (!documents.length) {
    const initial = {
      id: makeId(),
      title: "Untitled document",
      content: "<h1>Welcome to KodoWord</h1><p>Your document starts here.</p>",
      header: "",
      footer: "",
      updatedAt: Date.now()
    };
    documents.push(initial);
    currentId = initial.id;
    persistDocuments();
  }

  if (!documents.some(d => d.id === currentId)) {
    currentId = documents[0].id;
  }

  const fontStore = safeJsonParse(localStorage.getItem(FONT_KEY), []);
  if (Array.isArray(fontStore)) {
    fontStore.forEach(font => {
      if (font && font.name && font.data) installFont(font.name, font.data, false);
    });
  }

  renderDocs();
  openDocument(currentId);
}

function persistDocuments() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(documents));
    localStorage.setItem(CURRENT_KEY, currentId || "");
    return true;
  } catch (error) {
    console.error(error);
    showToast("Storage full. Export your document to keep a backup.");
    return false;
  }
}

function getCurrentDocument() {
  return documents.find(d => d.id === currentId);
}

function saveCurrentDocument() {
  const doc = getCurrentDocument();
  if (!doc) return;

  doc.title = titleInput.value.trim() || "Untitled document";
  doc.content = editor.innerHTML;
  doc.header = $("#pageHeader").innerHTML;
  doc.footer = $("#pageFooter").innerHTML;
  doc.updatedAt = Date.now();

  persistDocuments();
  renderDocs();
  setSaveStatus("Saved");
  updateCounts();
}

function scheduleSave() {
  setSaveStatus("Saving…");
  clearTimeout(saveTimer);
  saveTimer = setTimeout(saveCurrentDocument, 350);
}

function openDocument(id) {
  const doc = documents.find(d => d.id === id);
  if (!doc) return;

  if (currentId && currentId !== id) {
    clearTimeout(saveTimer);
    saveCurrentDocument();
  }

  currentId = id;
  titleInput.value = doc.title || "Untitled document";
  editor.innerHTML = doc.content || "<p><br></p>";
  $("#pageHeader").innerHTML = doc.header || "";
  $("#pageFooter").innerHTML = doc.footer || "";

  localStorage.setItem(CURRENT_KEY, currentId);
  renderDocs();
  updateCounts();
  clearObjectSelection();
  hideMenus();
  setSaveStatus("Saved");
}

function createDocument() {
  clearTimeout(saveTimer);
  saveCurrentDocument();

  const doc = {
    id: makeId(),
    title: "Untitled document",
    content: "<p><br></p>",
    header: "",
    footer: "",
    updatedAt: Date.now()
  };

  documents.unshift(doc);
  currentId = doc.id;
  persistDocuments();
  renderDocs();
  openDocument(doc.id);
  editor.focus();
  showToast("New document created");
}

function renderDocs() {
  docList.innerHTML = "";

  documents
    .slice()
    .sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))
    .forEach(doc => {
      const item = document.createElement("div");
      item.className = "doc-item" + (doc.id === currentId ? " active" : "");
      item.dataset.docId = doc.id;
      item.innerHTML = `
        <span class="doc-icon">▤</span>
        <span class="doc-item-name">${escapeHtml(doc.title || "Untitled document")}</span>
        <button class="doc-item-menu" type="button" aria-label="Document options" title="Document options">⋯</button>
      `;

      item.addEventListener("click", event => {
        if (event.target.closest(".doc-item-menu")) {
          event.stopPropagation();
          showDocumentMenu(doc.id, event.clientX || 180, event.clientY || 120);
          return;
        }
        if (doc.id !== currentId) openDocument(doc.id);
      });

      item.addEventListener("contextmenu", event => {
        event.preventDefault();
        showDocumentMenu(doc.id, event.clientX, event.clientY);
      });

      let startX = 0;
      let startY = 0;
      let longPressTriggered = false;

      item.addEventListener("pointerdown", event => {
        if (event.target.closest(".doc-item-menu")) return;
        startX = event.clientX;
        startY = event.clientY;
        longPressTriggered = false;
        clearTimeout(pressTimer);

        pressTimer = setTimeout(() => {
          longPressTriggered = true;
          showDocumentMenu(doc.id, startX, startY);
        }, 600);
      });

      item.addEventListener("pointermove", event => {
        if (Math.abs(event.clientX - startX) > 12 ||
            Math.abs(event.clientY - startY) > 12) {
          clearTimeout(pressTimer);
        }
      });

      ["pointerup", "pointercancel", "pointerleave"].forEach(type => {
        item.addEventListener(type, () => clearTimeout(pressTimer));
      });

      item.addEventListener("click", event => {
        if (longPressTriggered) {
          event.preventDefault();
          event.stopPropagation();
        }
      }, true);

      docList.appendChild(item);
    });
}

function showDocumentMenu(id, x, y) {
  activeDocumentMenuId = id;
  hideMenus();

  documentMenu.hidden = false;
  const width = 190;
  const height = 180;

  documentMenu.style.left = Math.max(8, Math.min(x, innerWidth - width - 8)) + "px";
  documentMenu.style.top = Math.max(8, Math.min(y, innerHeight - height - 8)) + "px";
}

function renameDocument(id) {
  const doc = documents.find(d => d.id === id);
  if (!doc) return;

  const newName = prompt("Enter a name for this document:", doc.title);
  if (newName === null) return;

  const trimmed = newName.trim();
  if (!trimmed) {
    showToast("Document name cannot be empty");
    return;
  }

  doc.title = trimmed;
  doc.updatedAt = Date.now();

  if (id === currentId) titleInput.value = trimmed;

  if (persistDocuments()) {
    renderDocs();
    showToast("Document renamed");
  }
}

function deleteDocument(id) {
  const doc = documents.find(d => d.id === id);
  if (!doc) return;

  if (!confirm(`Delete "${doc.title}"? This cannot be undone.`)) return;

  clearTimeout(saveTimer);

  // Save the current document before removing the selected document.
  if (id !== currentId) saveCurrentDocument();

  documents = documents.filter(d => d.id !== id);

  if (!documents.length) {
    const replacement = {
      id: makeId(),
      title: "Untitled document",
      content: "<p><br></p>",
      header: "",
      footer: "",
      updatedAt: Date.now()
    };
    documents = [replacement];
  }

  if (id === currentId) {
    currentId = documents[0].id;
  }

  persistDocuments();
  renderDocs();
  openDocument(currentId);
  showToast("Document deleted");
}

function duplicateDocument(id) {
  const doc = documents.find(d => d.id === id);
  if (!doc) return;

  const copy = {
    ...doc,
    id: makeId(),
    title: `${doc.title} (Copy)`,
    updatedAt: Date.now()
  };

  documents.unshift(copy);
  persistDocuments();
  renderDocs();
  openDocument(copy.id);
  showToast("Document duplicated");
}

$("#newDocBtn").addEventListener("click", createDocument);
$("#sidebarNewBtn").addEventListener("click", createDocument);
$("#homeBtn").addEventListener("click", () => openDocument(currentId));

titleInput.addEventListener("input", () => {
  const doc = getCurrentDocument();
  if (doc) doc.title = titleInput.value || "Untitled document";
  scheduleSave();
  renderDocs();
});

documentMenu.addEventListener("click", event => {
  const button = event.target.closest("[data-doc-action]");
  if (!button) return;

  const action = button.dataset.docAction;
  const id = activeDocumentMenuId;
  documentMenu.hidden = true;

  if (action === "rename") renameDocument(id);
  if (action === "duplicate") duplicateDocument(id);
  if (action === "delete") deleteDocument(id);
});

function hideMenus() {
  documentMenu.hidden = true;
  objectMenu.hidden = true;
}

document.addEventListener("pointerdown", event => {
  if (!event.target.closest("#documentMenu") &&
      !event.target.closest(".doc-item-menu")) {
    documentMenu.hidden = true;
  }

  if (!event.target.closest("#objectMenu") &&
      !event.target.closest(".object-selected")) {
    objectMenu.hidden = true;
  }
});

/* Selection helpers: retain text selection while toolbar controls are used. */

function saveSelection() {
  const selection = window.getSelection();
  if (!selection || !selection.rangeCount) return;

  const range = selection.getRangeAt(0);
  const container = range.commonAncestorContainer;
  const element = container.nodeType === Node.ELEMENT_NODE
    ? container
    : container.parentElement;

  if (element && (editor.contains(element) ||
      $("#pageHeader").contains(element) ||
      $("#pageFooter").contains(element))) {
    savedRange = range.cloneRange();
  }
}

function restoreSelection() {
  if (!savedRange) return false;

  try {
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(savedRange);
    return true;
  } catch {
    return false;
  }
}

document.addEventListener("selectionchange", () => {
  const selection = window.getSelection();
  if (!selection || !selection.rangeCount || selection.isCollapsed) return;

  const node = selection.getRangeAt(0).commonAncestorContainer;
  const element = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
  if (element && editor.contains(element)) saveSelection();
});

editor.addEventListener("keyup", saveSelection);
editor.addEventListener("mouseup", saveSelection);
editor.addEventListener("touchend", () => setTimeout(saveSelection, 0));

/* Formatting */

function focusEditorWithSelection() {
  editor.focus({ preventScroll: true });
  restoreSelection();
}

function runCommand(command, value = null) {
  focusEditorWithSelection();

  try {
    document.execCommand("styleWithCSS", false, true);
    document.execCommand(command, false, value);
  } catch (error) {
    console.error("Formatting command failed:", command, error);
  }

  saveSelection();
  scheduleSave();
  updateCounts();
}

$$("[data-cmd]").forEach(button => {
  button.addEventListener("pointerdown", () => saveSelection());
  button.addEventListener("click", () => runCommand(button.dataset.cmd));
});

$("#formatBlock").addEventListener("pointerdown", saveSelection);
$("#formatBlock").addEventListener("change", event => {
  runCommand("formatBlock", event.target.value);
});

$("#fontFamily").addEventListener("pointerdown", saveSelection);
$("#fontFamily").addEventListener("change", event => {
  runCommand("fontName", event.target.value);
});

function applyStyleToSelection(property, value) {
  focusEditorWithSelection();

  const selection = window.getSelection();
  if (!selection || !selection.rangeCount) return;

  const range = selection.getRangeAt(0);

  if (range.collapsed) {
    showToast("Select some text first");
    return;
  }

  // Extracting the selection into a span applies styling to only selected text.
  const span = document.createElement("span");
  span.style[property] = value;

  try {
    const fragment = range.extractContents();
    span.appendChild(fragment);
    range.insertNode(span);

    const newRange = document.createRange();
    newRange.selectNodeContents(span);
    selection.removeAllRanges();
    selection.addRange(newRange);
    savedRange = newRange.cloneRange();
  } catch (error) {
    console.error(error);
    showToast("Could not apply formatting to that selection");
  }

  scheduleSave();
}

$("#fontSize").addEventListener("pointerdown", saveSelection);
$("#fontSize").addEventListener("change", event => {
  const size = Math.max(6, Math.min(200, Number(event.target.value) || 12));
  event.target.value = size;
  applyStyleToSelection("fontSize", `${size}pt`);
});

$("#textColor").addEventListener("pointerdown", saveSelection);
$("#textColor").addEventListener("input", event => {
  $("#textColor").dataset.pendingColor = event.target.value;
});
$("#textColor").addEventListener("change", event => {
  applyStyleToSelection("color", event.target.value);
  $(".color-underline").style.background = event.target.value;
});

$("#highlightColor").addEventListener("pointerdown", saveSelection);
$("#highlightColor").addEventListener("change", event => {
  applyStyleToSelection("backgroundColor", event.target.value);
  $(".highlight-underline").style.background = event.target.value;
});

$("#lineSpacing").addEventListener("pointerdown", saveSelection);
$("#lineSpacing").addEventListener("change", event => {
  focusEditorWithSelection();

  const selection = window.getSelection();
  let block = null;

  if (selection && selection.rangeCount) {
    let node = selection.getRangeAt(0).startContainer;
    if (node.nodeType !== Node.ELEMENT_NODE) node = node.parentElement;
    block = node?.closest("p,h1,h2,h3,h4,h5,h6,li,blockquote,div");
  }

  if (!block || !editor.contains(block)) {
    showToast("Place the cursor inside a paragraph first");
    return;
  }

  block.style.lineHeight = event.target.value;
  scheduleSave();
});

$("#clearFormatBtn").addEventListener("click", () => {
  focusEditorWithSelection();
  runCommand("removeFormat");
  runCommand("unlink");
});

/* Import a custom font and make it available in the font menu. */

function installFont(name, data, saveToStorage = true) {
  const family = name.replace(/[^a-zA-Z0-9_-]/g, "_");
  const styleId = "custom-font-" + family;

  let style = document.getElementById(styleId);
  if (!style) {
    style = document.createElement("style");
    style.id = styleId;
    document.head.appendChild(style);
  }

  style.textContent = `
    @font-face {
      font-family: "${family}";
      src: url("${data}");
      font-display: swap;
    }
  `;

  const select = $("#fontFamily");
  if (![...select.options].some(option => option.value === family)) {
    const option = document.createElement("option");
    option.value = family;
    option.textContent = name;
    select.appendChild(option);
  }

  if (saveToStorage) {
    const fonts = safeJsonParse(localStorage.getItem(FONT_KEY), []);
    const existing = Array.isArray(fonts)
      ? fonts.filter(font => font.name !== name)
      : [];

    existing.push({ name: family, data });
    try {
      localStorage.setItem(FONT_KEY, JSON.stringify(existing));
    } catch (error) {
      console.error(error);
      showToast("Font loaded, but storage is full. It may not persist after reload.");
    }
  }

  return family;
}

$("#importFontBtn").addEventListener("click", () => $("#fontInput").click());

$("#fontInput").addEventListener("change", async event => {
  const file = event.target.files?.[0];
  if (!file) return;

  const allowed = /\.(ttf|otf|woff|woff2)$/i.test(file.name);
  if (!allowed) {
    showToast("Choose a TTF, OTF, WOFF or WOFF2 font file");
    event.target.value = "";
    return;
  }

  if (file.size > 8 * 1024 * 1024) {
    showToast("Font file is too large (maximum 8 MB)");
    event.target.value = "";
    return;
  }

  const reader = new FileReader();

  reader.onload = () => {
    const rawName = file.name.replace(/\.(ttf|otf|woff2?)$/i, "");
    const family = installFont(rawName, reader.result);

    $("#fontFamily").value = family;
    showToast(`Font "${rawName}" imported. Select text to apply it.`);
    event.target.value = "";
  };

  reader.onerror = () => showToast("Could not read the font file");
  reader.readAsDataURL(file);
});

/* Images */

$("#insertImageBtn").addEventListener("click", () => $("#imageInput").click());

$("#imageInput").addEventListener("change", event => {
  const file = event.target.files?.[0];
  if (!file) return;

  if (!file.type.startsWith("image/")) {
    showToast("Choose an image file");
    event.target.value = "";
    return;
  }

  if (file.size > 8 * 1024 * 1024) {
    showToast("Image is too large (maximum 8 MB)");
    event.target.value = "";
    return;
  }

  const reader = new FileReader();
  reader.onload = () => {
    focusEditorWithSelection();

    const img = document.createElement("img");
    img.src = reader.result;
    img.alt = file.name;
    img.style.maxWidth = "100%";
    img.style.height = "auto";
    img.style.display = "block";
    img.style.margin = "8px 0";
    img.dataset.kodowordObject = "image";

    const selection = window.getSelection();
    if (selection && selection.rangeCount) {
      const range = selection.getRangeAt(0);
      range.deleteContents();
      range.insertNode(img);
      range.setStartAfter(img);
      range.collapse(true);
      selection.removeAllRanges();
      selection.addRange(range);
    } else {
      editor.appendChild(img);
    }

    scheduleSave();
    showToast("Image inserted");
  };

  reader.onerror = () => showToast("Could not read image");
  reader.readAsDataURL(file);
  event.target.value = "";
});

/* Tables */

$("#insertTableBtn").addEventListener("click", () => {
  $("#tableOverlay").hidden = false;
});

$("#createTableBtn").addEventListener("click", () => {
  const rows = Math.max(1, Math.min(30, Number($("#tableRows").value) || 3));
  const cols = Math.max(1, Math.min(15, Number($("#tableCols").value) || 3));

  const table = document.createElement("table");
  table.dataset.kodowordObject = "table";

  const tbody = document.createElement("tbody");

  for (let r = 0; r < rows; r++) {
    const tr = document.createElement("tr");
    for (let c = 0; c < cols; c++) {
      const td = document.createElement("td");
      td.innerHTML = "<br>";
      tr.appendChild(td);
    }
    tbody.appendChild(tr);
  }

  table.appendChild(tbody);
  focusEditorWithSelection();

  const selection = window.getSelection();
  if (selection && selection.rangeCount) {
    const range = selection.getRangeAt(0);
    range.deleteContents();
    range.insertNode(table);
    const paragraph = document.createElement("p");
    paragraph.innerHTML = "<br>";
    table.after(paragraph);
  } else {
    editor.appendChild(table);
  }

  $("#tableOverlay").hidden = true;
  scheduleSave();
  showToast("Table inserted");
});

/* Links */

$("#insertLinkBtn").addEventListener("pointerdown", saveSelection);
$("#insertLinkBtn").addEventListener("click", () => {
  focusEditorWithSelection();

  const url = prompt("Enter the URL (including https://):");
  if (!url) return;

  let safeUrl;
  try {
    safeUrl = new URL(url);
    if (!["http:", "https:", "mailto:"].includes(safeUrl.protocol)) {
      showToast("Only HTTP, HTTPS or email links are supported");
      return;
    }
  } catch {
    showToast("Enter a valid URL, e.g. https://example.com");
    return;
  }

  runCommand("createLink", safeUrl.href);
});

/* Page setup */

$("#pageSetupBtn").addEventListener("click", () => {
  $("#paperSize").value = pageConfig.size;
  $("#pageOrientation").value = pageConfig.orientation;
  $("#pageMargin").value = pageConfig.margin;
  $("#pageSetupOverlay").hidden = false;
});

function applyPageConfig() {
  pageConfig.size = $("#paperSize").value;
  pageConfig.orientation = $("#pageOrientation").value;
  pageConfig.margin = Math.max(5, Math.min(50, Number($("#pageMargin").value) || 20));

  const sizes = {
    a4: [210, 297],
    letter: [215.9, 279.4],
    legal: [215.9, 355.6]
  };

  let [width, height] = sizes[pageConfig.size] || sizes.a4;
  if (pageConfig.orientation === "landscape") [width, height] = [height, width];

  page.style.width = `${width}mm`;
  page.style.minHeight = `${height}mm`;
  page.style.padding = `${pageConfig.margin}mm`;

  $("#pageSetupOverlay").hidden = true;
  scheduleSave();
  showToast("Page setup applied");
}

$("#applyPageSetupBtn").addEventListener("click", applyPageConfig);

/* Search and replace */

$("#findBtn").addEventListener("click", () => {
  $("#findPanel").hidden = !$("#findPanel").hidden;
  if (!$("#findPanel").hidden) $("#findText").focus();
});

$("#closeFindBtn").addEventListener("click", () => {
  $("#findPanel").hidden = true;
});

$("#findNextBtn").addEventListener("click", () => {
  const query = $("#findText").value;
  if (!query) return;

  editor.focus();
  const found = window.find(query, false, false, true, false, false, false);
  if (!found) showToast("No more matches found");
});

$("#replaceBtn").addEventListener("click", () => {
  const query = $("#findText").value;
  if (!query) return;

  const selection = window.getSelection();
  if (selection && selection.toString().toLowerCase() === query.toLowerCase()) {
    const range = selection.getRangeAt(0);
    range.deleteContents();
    range.insertNode(document.createTextNode($("#replaceText").value));
    scheduleSave();
    showToast("Text replaced");
  } else {
    $("#findNextBtn").click();
    showToast("Find a matching selection, then press Replace again");
  }
});

$("#replaceAllBtn").addEventListener("click", () => {
  const query = $("#findText").value;
  if (!query) return;

  const replacement = $("#replaceText").value;
  const walker = document.createTreeWalker(editor, NodeFilter.SHOW_TEXT);
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);

  let count = 0;
  nodes.forEach(node => {
    const parent = node.parentElement;
    if (!parent || parent.closest("script,style")) return;

    const original = node.nodeValue;
    const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const regex = new RegExp(escaped, "gi");

    if (regex.test(original)) {
      node.nodeValue = original.replace(regex, () => {
        count++;
        return replacement;
      });
    }
  });

  scheduleSave();
  showToast(`${count} replacement(s) made`);
});

/* Object selection, menus, long-press and dragging */

function clearObjectSelection() {
  $$(".object-selected", editor).forEach(el => el.classList.remove("object-selected"));
  selectedObject = null;
}

function selectObject(element, x, y) {
  if (!element || !editor.contains(element)) return;

  clearObjectSelection();
  selectedObject = element;
  selectedObject.classList.add("object-selected");

  objectMenu.hidden = false;
  objectMenu.style.left = Math.max(8, Math.min(x, innerWidth - 198)) + "px";
  objectMenu.style.top = Math.max(8, Math.min(y, innerHeight - 190)) + "px";
}

function getEditableObject(node) {
  let element = node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement;
  if (!element) return null;

  const object = element.closest("img,table");
  return object && editor.contains(object) ? object : null;
}

editor.addEventListener("contextmenu", event => {
  const object = getEditableObject(event.target);
  if (!object) return;
  event.preventDefault();
  selectObject(object, event.clientX, event.clientY);
});

editor.addEventListener("pointerdown", event => {
  const object = getEditableObject(event.target);
  if (!object) return;

  pressOrigin = { x: event.clientX, y: event.clientY, object };
  clearTimeout(pressTimer);

  pressTimer = setTimeout(() => {
    selectObject(object, event.clientX, event.clientY);
  }, 650);
});

editor.addEventListener("pointermove", event => {
  if (!pressOrigin) return;

  if (Math.abs(event.clientX - pressOrigin.x) > 12 ||
      Math.abs(event.clientY - pressOrigin.y) > 12) {
    clearTimeout(pressTimer);
  }
});

["pointerup", "pointercancel", "pointerleave"].forEach(type => {
  editor.addEventListener(type, () => {
    clearTimeout(pressTimer);
    pressOrigin = null;
  });
});

objectMenu.addEventListener("click", event => {
  const button = event.target.closest("[data-object-action]");
  if (!button || !selectedObject) return;

  const action = button.dataset.objectAction;
  const object = selectedObject;
  objectMenu.hidden = true;

  if (action === "close") {
    clearObjectSelection();
    return;
  }

  if (action === "delete") {
    object.remove();
    clearObjectSelection();
    scheduleSave();
    showToast("Object deleted");
    return;
  }

  if (action === "front") {
    object.style.position = "relative";
    object.style.zIndex = String(++objectZIndex);
    scheduleSave();
    return;
  }

  if (action === "back") {
    object.style.position = "relative";
    object.style.zIndex = "0";
    scheduleSave();
    return;
  }

  if (action === "move") {
    showToast("Drag the selected object to move it");
    object.draggable = true;
  }
});

// Drag images/tables on devices supporting HTML drag-and-drop.
editor.addEventListener("dragstart", event => {
  const object = getEditableObject(event.target);
  if (!object) return;

  draggedObject = object;
  event.dataTransfer?.setData("text/plain", "kodoword-object");
  if (event.dataTransfer) event.dataTransfer.effectAllowed = "move";
});

editor.addEventListener("dragover", event => {
  if (!draggedObject) return;
  event.preventDefault();
  if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
});

editor.addEventListener("drop", event => {
  if (!draggedObject) return;
  event.preventDefault();

  const target = document.elementFromPoint(event.clientX, event.clientY);
  const targetObject = getEditableObject(target);

  if (targetObject && targetObject !== draggedObject) {
    const rect = targetObject.getBoundingClientRect();
    if (event.clientY < rect.top + rect.height / 2) {
      targetObject.before(draggedObject);
    } else {
      targetObject.after(draggedObject);
    }
  } else if (target && editor.contains(target)) {
    const range = document.caretRangeFromPoint?.(event.clientX, event.clientY);
    if (range) {
      range.insertNode(draggedObject);
    } else {
      editor.appendChild(draggedObject);
    }
  }

  draggedObject.draggable = false;
  draggedObject = null;
  scheduleSave();
});

editor.addEventListener("click", event => {
  const object = getEditableObject(event.target);
  if (!object) {
    if (!event.target.closest("#objectMenu")) clearObjectSelection();
    return;
  }

  // A normal click selects the object; the menu can also be opened by long-press.
  clearObjectSelection();
  selectedObject = object;
  object.classList.add("object-selected");
});

document.addEventListener("click", event => {
  if (!event.target.closest("#objectMenu") &&
      !event.target.closest("#editor img") &&
      !event.target.closest("#editor table")) {
    objectMenu.hidden = true;
  }
});

/* Keep object menu useful on touch screens: selected objects can be deleted,
   moved in the document and brought forward/backward. */

/* Counts and autosave */

function updateCounts() {
  const text = editor.innerText || "";
  const trimmed = text.trim();
  const words = trimmed ? trimmed.split(/\s+/).length : 0;

  $("#wordCount").textContent = `${words} word${words === 1 ? "" : "s"}`;
  $("#charCount").textContent = `${text.length} characters`;
}

editor.addEventListener("input", () => {
  scheduleSave();
  updateCounts();
});
$("#pageHeader").addEventListener("input", scheduleSave);
$("#pageFooter").addEventListener("input", scheduleSave);

/* Export helpers */

function makeExportDocument() {
  const header = $("#pageHeader").innerHTML;
  const footer = $("#pageFooter").innerHTML;
  const bodyContent = editor.innerHTML;

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(titleInput.value || "KodoWord document")}</title>
<style>
  body { font-family: Arial, sans-serif; color: #202124; line-height: 1.5; }
  .page-header, .page-footer { color: #777; font-size: 10pt; }
  .page-header { margin-bottom: 22px; }
  .page-footer { margin-top: 30px; }
  img { max-width: 100%; height: auto; }
  table { border-collapse: collapse; max-width: 100%; }
  td, th { border: 1px solid #777; padding: 6px; vertical-align: top; }
  blockquote { border-left: 4px solid #a6baff; padding: 8px 14px; color: #5c6475; }
  @page { size: ${pageConfig.size} ${pageConfig.orientation}; margin: ${pageConfig.margin}mm; }
</style>
</head>
<body>
<div class="page-header">${header}</div>
<main>${bodyContent}</main>
<div class="page-footer">${footer}</div>
</body>
</html>`;
}

function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1500);
}

function fileBaseName() {
  const name = (titleInput.value || "KodoWord document")
    .replace(/[\\/:*?"<>|]+/g, "_")
    .trim();

  return name || "KodoWord document";
}

function exportHTML() {
  const html = makeExportDocument();
  downloadBlob(new Blob([html], { type: "text/html;charset=utf-8" }), `${fileBaseName()}.html`);
  showToast("HTML downloaded");
}

function exportTXT() {
  const text = [
    $("#pageHeader").innerText,
    editor.innerText,
    $("#pageFooter").innerText
  ].filter(Boolean).join("\n\n");

  downloadBlob(new Blob([text], { type: "text/plain;charset=utf-8" }), `${fileBaseName()}.txt`);
  showToast("TXT downloaded");
}

function exportWordCompatibleHTML() {
  const html = makeExportDocument();
  downloadBlob(
    new Blob(["\ufeff", html], { type: "application/msword;charset=utf-8" }),
    `${fileBaseName()}.doc`
  );
  showToast("Word-compatible file downloaded");
}

async function exportPDF() {
  if (typeof window.html2pdf !== "function") {
    showToast("PDF library did not load. Check your internet connection and reload.");
    return;
  }

  saveCurrentDocument();
  setSaveStatus("Preparing PDF…");

  const clone = page.cloneNode(true);
  clone.id = "pdf-export-page";
  clone.classList.add("pdf-export-mode");

  // Remove editor-only outlines and contenteditable attributes in the PDF copy.
  clone.querySelectorAll("[contenteditable]").forEach(el => {
    el.removeAttribute("contenteditable");
  });
  clone.querySelectorAll(".object-selected").forEach(el => {
    el.classList.remove("object-selected");
  });
  clone.querySelectorAll("img").forEach(img => {
    img.style.maxWidth = "100%";
    img.style.height = "auto";
  });

  const wrapper = document.createElement("div");
  wrapper.style.position = "fixed";
  wrapper.style.left = "-100000px";
  wrapper.style.top = "0";
  wrapper.style.width = "fit-content";
  wrapper.style.background = "#fff";
  wrapper.appendChild(clone);
  document.body.appendChild(wrapper);

  const format = {
    a4: "a4",
    letter: "letter",
    legal: "legal"
  }[pageConfig.size] || "a4";

  try {
    await window.html2pdf()
      .set({
        margin: 0,
        filename: `${fileBaseName()}.pdf`,
        image: { type: "jpeg", quality: 0.96 },
        html2canvas: {
          scale: 1.6,
          useCORS: true,
          backgroundColor: "#ffffff",
          logging: false,
          scrollX: 0,
          scrollY: 0
        },
        jsPDF: {
          unit: "mm",
          format,
          orientation: pageConfig.orientation,
          compress: true
        },
        pagebreak: {
          mode: ["css", "legacy"],
          avoid: ["img", "table", "tr"]
        }
      })
      .from(clone)
      .save();

    showToast("PDF download started");
  } catch (error) {
    console.error("PDF export failed:", error);
    showToast("PDF export failed. Try HTML export or check available memory.");
  } finally {
    wrapper.remove();
    setSaveStatus("Saved");
  }
}

function printDocument() {
  const html = makeExportDocument();
  const printWindow = window.open("", "_blank");

  if (!printWindow) {
    showToast("Popup blocked. Allow popups to print this document.");
    return;
  }

  printWindow.document.open();
  printWindow.document.write(html);
  printWindow.document.close();

  printWindow.onload = () => {
    printWindow.focus();
    printWindow.print();
  };
}

$("#exportBtn").addEventListener("click", () => {
  saveCurrentDocument();
  $("#exportOverlay").hidden = false;
});

$$("[data-export]").forEach(button => {
  button.addEventListener("click", async () => {
    const type = button.dataset.export;
    $("#exportOverlay").hidden = true;

    if (type === "pdf") await exportPDF();
    if (type === "html") exportHTML();
    if (type === "txt") exportTXT();
    if (type === "docx") exportWordCompatibleHTML();
    if (type === "print") printDocument();
  });
});

/* Close modal buttons and click-outside behaviour */

$$("[data-close]").forEach(button => {
  button.addEventListener("click", () => {
    const target = document.getElementById(button.dataset.close);
    if (target) target.hidden = true;
  });
});

$$(".overlay").forEach(overlay => {
  overlay.addEventListener("click", event => {
    if (event.target === overlay) overlay.hidden = true;
  });
});

document.addEventListener("keydown", event => {
  const modifier = event.ctrlKey || event.metaKey;

  if (event.key === "Escape") {
    hideMenus();
    $$(".overlay").forEach(overlay => overlay.hidden = true);
  }

  if (modifier && event.key.toLowerCase() === "s") {
    event.preventDefault();
    clearTimeout(saveTimer);
    saveCurrentDocument();
    showToast("Document saved");
  }

  if (modifier && event.key.toLowerCase() === "b") {
    event.preventDefault();
    runCommand("bold");
  }

  if (modifier && event.key.toLowerCase() === "i") {
    event.preventDefault();
    runCommand("italic");
  }

  if (modifier && event.key.toLowerCase() === "u") {
    event.preventDefault();
    runCommand("underline");
  }

  if (modifier && event.key.toLowerCase() === "f") {
    event.preventDefault();
    $("#findPanel").hidden = false;
    $("#findText").focus();
  }

  if (modifier && event.key.toLowerCase() === "p") {
    event.preventDefault();
    printDocument();
  }
});

window.addEventListener("beforeunload", () => {
  clearTimeout(saveTimer);
  saveCurrentDocument();
});

/* Start app */

loadDocuments();
updateCounts();


// Word-style side formatting controls
(() => {
  const sideFont = document.getElementById('sideFontFamily');
  const sideSize = document.getElementById('sideFontSize');
  const sideText = document.getElementById('sideTextColor');
  const sideHighlight = document.getElementById('sideHighlightColor');
  const sideLine = document.getElementById('sideLineSpacing');
  const mirror = (a,b,evt='change') => { const x=document.getElementById(a), y=document.getElementById(b); if(x&&y){x.addEventListener(evt,()=>{y.value=x.value;y.dispatchEvent(new Event('change',{bubbles:true}));});} };
  mirror('sideFontFamily','fontFamily'); mirror('sideFontSize','fontSize'); mirror('sideTextColor','textColor'); mirror('sideHighlightColor','highlightColor'); mirror('sideLineSpacing','lineSpacing');
  document.getElementById('sideSizeDown')?.addEventListener('click',()=>{const x=document.getElementById('fontSize');x.value=Math.max(6,(+x.value||12)-1);x.dispatchEvent(new Event('change',{bubbles:true}));sideSize.value=x.value;});
  document.getElementById('sideSizeUp')?.addEventListener('click',()=>{const x=document.getElementById('fontSize');x.value=Math.min(200,(+x.value||12)+1);x.dispatchEvent(new Event('change',{bubbles:true}));sideSize.value=x.value;});
  document.getElementById('sideImportFont')?.addEventListener('click',()=>document.getElementById('importFontBtn')?.click());
  document.querySelectorAll('.side-style [data-cmd]').forEach(b=>b.addEventListener('click',()=>{const target=document.querySelector('.toolbar-wrap [data-cmd="'+b.dataset.cmd+'"]');target?.click();}));
  document.querySelectorAll('.ribbon-tab').forEach(b=>b.addEventListener('click',()=>{document.querySelectorAll('.ribbon-tab').forEach(t=>t.classList.toggle('active',t===b));}));
  // Keep the starter document minimal without erasing user-authored documents.
  try { const key='kodoword_documents_v3'; const docs=JSON.parse(localStorage.getItem(key)||'[]'); let changed=false; for(const d of docs){ if(d && typeof d.content==='string' && /Welcome to KodoWord|Your document starts here/.test(d.content)){ d.content='<h1>KodoWord</h1><p>Document Editor</p>'; changed=true; } } if(changed)localStorage.setItem(key,JSON.stringify(docs)); } catch(e) {}
})();
