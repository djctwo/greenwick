// Greenwick site: mobile menu toggle and screenshot lightbox. No tracking, no dependencies.
(function () {
    var btn = document.querySelector('.menu-btn');
    var links = document.getElementById('nav-links');
    if (btn && links) {
        btn.addEventListener('click', function () {
            var open = links.classList.toggle('open');
            btn.setAttribute('aria-expanded', open ? 'true' : 'false');
        });
        document.addEventListener('keydown', function (e) {
            if (e.key === 'Escape' && links.classList.contains('open')) {
                links.classList.remove('open');
                btn.setAttribute('aria-expanded', 'false');
                btn.focus();
            }
        });
    }

    // Screenshot links open the full image in a dialog; without JS (or without
    // <dialog> support) they simply open the image file.
    var dialog = document.getElementById('lightbox');
    if (!dialog || typeof dialog.showModal !== 'function') return;
    var big = dialog.querySelector('img');
    document.querySelectorAll('a[data-zoom]').forEach(function (a) {
        a.addEventListener('click', function (e) {
            e.preventDefault();
            var img = a.querySelector('img');
            big.src = a.getAttribute('href');
            big.alt = img ? img.alt : '';
            dialog.showModal();
        });
    });
    dialog.addEventListener('click', function (e) {
        if (e.target === dialog || e.target === big) dialog.close();
    });
    dialog.addEventListener('close', function () { big.removeAttribute('src'); });
})();
