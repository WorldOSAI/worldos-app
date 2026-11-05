(() => {
  const retry = document.getElementById("retry");
  const label = retry.textContent;
  let pending = false;
  let deadline;

  function reset() {
    clearTimeout(deadline);
    pending = false;
    retry.disabled = false;
    retry.textContent = label;
  }

  function retryTarget() {
    // Capacitor.getServerUrl() is the asset origin (capacitor://localhost on
    // iOS), not the configured remote service. iOS injects its actual target;
    // the production URL also supports Android and older native shells.
    let url;
    try {
      url = new URL(window.WorldOSAppServerURL || "https://worldos.cc");
      if (!["https:", "http:"].includes(url.protocol) || url.username || url.password) throw new Error("invalid service URL");
    } catch (_) {
      url = new URL("https://worldos.cc");
    }
    url.searchParams.set("native-retry", Date.now().toString());
    return url.toString();
  }

  function reconnect() {
    if (pending) return;
    pending = true;
    retry.disabled = true;
    retry.textContent = "Connecting…";
    // Navigate directly: a preflight fetch from the local asset origin can fail
    // independently (CORS/custom schemes), or hang and leave Retry disabled.
    // If navigation stalls, let the person try again without killing the app.
    deadline = setTimeout(reset, 10000);
    try {
      location.replace(retryTarget());
    } catch (_) {
      reset();
    }
  }

  retry.addEventListener("click", reconnect);
  window.addEventListener("online", () => { reset(); reconnect(); });
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") { reset(); reconnect(); }
  });
  window.addEventListener("pagehide", () => clearTimeout(deadline));
  window.addEventListener("pageshow", reset);
})();
