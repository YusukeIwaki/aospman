(() => {
  "use strict";

  const toast = document.querySelector("#toast");
  let conditionalController = null;

  function bufferToBase64url(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = "";
    bytes.forEach((byte) => { binary += String.fromCharCode(byte); });
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }

  function base64urlToBuffer(value) {
    const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
    const padding = "=".repeat((4 - normalized.length % 4) % 4);
    const binary = atob(normalized + padding);
    return Uint8Array.from(binary, (char) => char.charCodeAt(0)).buffer;
  }

  function creationOptionsFromJSON(options) {
    return {
      ...options,
      challenge: base64urlToBuffer(options.challenge),
      user: { ...options.user, id: base64urlToBuffer(options.user.id) },
      excludeCredentials: (options.excludeCredentials || []).map((credential) => ({
        ...credential,
        id: base64urlToBuffer(credential.id)
      }))
    };
  }

  function requestOptionsFromJSON(options) {
    return {
      ...options,
      challenge: base64urlToBuffer(options.challenge),
      allowCredentials: (options.allowCredentials || []).map((credential) => ({
        ...credential,
        id: base64urlToBuffer(credential.id)
      }))
    };
  }

  function credentialToJSON(credential) {
    const response = credential.response;
    const serialized = {
      id: credential.id,
      rawId: bufferToBase64url(credential.rawId),
      type: credential.type,
      authenticatorAttachment: credential.authenticatorAttachment,
      clientExtensionResults: credential.getClientExtensionResults(),
      response: {
        clientDataJSON: bufferToBase64url(response.clientDataJSON)
      }
    };

    if (response.attestationObject) {
      serialized.response.attestationObject = bufferToBase64url(response.attestationObject);
      serialized.response.transports = typeof response.getTransports === "function" ? response.getTransports() : [];
    } else {
      serialized.response.authenticatorData = bufferToBase64url(response.authenticatorData);
      serialized.response.signature = bufferToBase64url(response.signature);
      serialized.response.userHandle = response.userHandle ? bufferToBase64url(response.userHandle) : null;
    }

    return serialized;
  }

  async function postJSON(path, payload) {
    const response = await fetch(path, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "Accept": "application/json" },
      body: JSON.stringify(payload)
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
    return body;
  }

  function showToast(message, kind = "info") {
    if (!toast) return;
    toast.textContent = message;
    toast.dataset.kind = kind;
    toast.hidden = false;
    window.clearTimeout(showToast.timeout);
    showToast.timeout = window.setTimeout(() => { toast.hidden = true; }, 6000);
  }

  function setBusy(form, busy) {
    form.querySelectorAll("button, input").forEach((element) => { element.disabled = busy; });
    const button = form.querySelector("button[type='submit']");
    if (button) button.classList.toggle("busy", busy);
  }

  function humanizeCredentialError(error) {
    if (error.name === "NotAllowedError") return "操作がキャンセルされたか、認証がタイムアウトしました。";
    if (error.name === "InvalidStateError") return "この端末には同じパスキーがすでに登録されています。";
    if (error.name === "SecurityError") return "WebAuthn の RP ID または Origin が一致しません。";
    return error.message || "パスキーの処理に失敗しました。";
  }

  async function finishLogin(credential) {
    const result = await postJSON("/api/login/verify", { credential: credentialToJSON(credential) });
    window.location.assign(result.redirect);
  }

  async function startConditionalLogin() {
    const status = document.querySelector("#autofill-status");
    if (!status || !window.PublicKeyCredential || !navigator.credentials) return;
    if (typeof PublicKeyCredential.isConditionalMediationAvailable !== "function") {
      status.textContent = "このブラウザはパスキー autofill の対応を通知していません。通常ログインは試せます。";
      return;
    }

    const available = await PublicKeyCredential.isConditionalMediationAvailable();
    if (!available) {
      status.textContent = "このブラウザではパスキー autofill を利用できません。通常ログインは試せます。";
      return;
    }

    const result = await postJSON("/api/login/options", {});
    conditionalController = new AbortController();
    status.textContent = "Autofill 待機中：ユーザー名欄をタップしてパスキー候補を確認してください。";
    const credential = await navigator.credentials.get({
      publicKey: requestOptionsFromJSON(result.publicKey),
      mediation: "conditional",
      signal: conditionalController.signal
    });
    if (credential) await finishLogin(credential);
  }

  function setupTabs() {
    const tabs = Array.from(document.querySelectorAll("[role='tab']"));
    tabs.forEach((tab) => {
      tab.addEventListener("click", () => {
        tabs.forEach((candidate) => {
          const active = candidate === tab;
          candidate.classList.toggle("active", active);
          candidate.setAttribute("aria-selected", String(active));
          document.querySelector(`#${candidate.getAttribute("aria-controls")}`).hidden = !active;
        });
      });
    });
  }

  function setupRegistration() {
    const form = document.querySelector("#register-form");
    if (!form) return;
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      setBusy(form, true);
      try {
        if (conditionalController) conditionalController.abort();
        const username = new FormData(form).get("username");
        const result = await postJSON("/api/register/options", { username });
        const credential = await navigator.credentials.create({
          publicKey: creationOptionsFromJSON(result.publicKey)
        });
        const verified = await postJSON("/api/register/verify", { credential: credentialToJSON(credential) });
        window.location.assign(verified.redirect);
      } catch (error) {
        if (error.name !== "AbortError") showToast(humanizeCredentialError(error), "error");
        setBusy(form, false);
      }
    });
  }

  function setupLogin() {
    const form = document.querySelector("#login-form");
    if (!form) return;
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      setBusy(form, true);
      try {
        if (conditionalController) conditionalController.abort();
        const username = new FormData(form).get("username");
        const result = await postJSON("/api/login/options", { username });
        const credential = await navigator.credentials.get({
          publicKey: requestOptionsFromJSON(result.publicKey)
        });
        await finishLogin(credential);
      } catch (error) {
        if (error.name !== "AbortError") showToast(humanizeCredentialError(error), "error");
        setBusy(form, false);
      }
    });
  }

  async function showCapabilities() {
    const webauthn = document.querySelector("#webauthn-support");
    const conditional = document.querySelector("#conditional-support");
    if (!webauthn || !conditional) return;

    const supported = Boolean(window.PublicKeyCredential && navigator.credentials);
    webauthn.textContent = supported ? "WebAuthn 対応" : "WebAuthn 非対応";
    webauthn.className = `capability ${supported ? "supported" : "unsupported"}`;

    let conditionalSupported = false;
    if (supported && typeof PublicKeyCredential.isConditionalMediationAvailable === "function") {
      conditionalSupported = await PublicKeyCredential.isConditionalMediationAvailable().catch(() => false);
    }
    conditional.textContent = conditionalSupported ? "Autofill 対応" : "Autofill 未対応";
    conditional.className = `capability ${conditionalSupported ? "supported" : "unsupported"}`;
  }

  if (document.body.dataset.page === "home") {
    setupTabs();
    setupRegistration();
    setupLogin();
    showCapabilities();
    startConditionalLogin().catch((error) => {
      if (error.name !== "AbortError" && error.name !== "NotAllowedError") {
        const status = document.querySelector("#autofill-status");
        if (status) status.textContent = `Autofill を開始できませんでした: ${error.message}`;
      }
    });
  }
})();
