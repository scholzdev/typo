(function () {
  var KEY = "typo-guide-theme", root = document.documentElement;
  var btns = document.querySelectorAll(".theme-switch button");
  function show(v) {
    for (var i = 0; i < btns.length; i++) btns[i].setAttribute("aria-pressed", String(btns[i].dataset.theme === v));
  }
  var saved = root.getAttribute("data-theme");
  show(saved === "light" || saved === "dark" ? saved : "auto");
  for (var i = 0; i < btns.length; i++) btns[i].addEventListener("click", function () {
    var v = this.dataset.theme;
    if (v === "auto") root.removeAttribute("data-theme"); else root.setAttribute("data-theme", v);
    show(v);
    try { if (v === "auto") localStorage.removeItem(KEY); else localStorage.setItem(KEY, v); } catch (e) {}
  });
})();
