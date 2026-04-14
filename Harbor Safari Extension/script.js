(function () {
    if (
        typeof safari === "undefined" ||
        !safari.extension ||
        typeof safari.extension.setContextMenuEventUserInfo !== "function"
    ) {
        return;
    }

    function closestLink(fromEventTarget) {
        var node = fromEventTarget;

        if (node && node.nodeType === Node.TEXT_NODE) {
            node = node.parentElement;
        }

        while (node && node !== document) {
            if (typeof node.closest === "function") {
                return node.closest("a[href]");
            }

            if (
                node.nodeType === Node.ELEMENT_NODE &&
                node.tagName &&
                node.tagName.toLowerCase() === "a" &&
                node.hasAttribute("href")
            ) {
                return node;
            }

            node = node.parentElement;
        }

        return null;
    }

    function absoluteURL(anchor) {
        if (!anchor) {
            return null;
        }

        try {
            return new URL(anchor.getAttribute("href"), document.baseURI).href;
        } catch (error) {
            return null;
        }
    }

    document.addEventListener(
        "contextmenu",
        function (event) {
            var href = absoluteURL(closestLink(event.target));
            safari.extension.setContextMenuEventUserInfo(
                event,
                href ? { linkHref: href } : {}
            );
        },
        true
    );
})();
