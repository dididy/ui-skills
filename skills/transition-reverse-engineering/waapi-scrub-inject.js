/**
 * waapi-scrub-inject.js
 *
 * Inject into a page after load to enable WAAPI time scrubbing.
 * Useful for page-load animations that complete before any screenshot is possible.
 *
 * Usage (agent-browser):
 *   agent-browser eval "$(cat waapi-scrub-inject.js)"
 *
 * NOTE: `$(cat waapi-scrub-inject.js)` is safe — shell does not expand % inside command
 * substitution output. However, if agent-browser itself parses % in its eval argument,
 * write the script to a temp file and pass the path instead.
 *
 * After injection, window.__scrub is available:
 *   window.__scrub.setup(configs)  — cancel existing anims, create paused ones
 *   window.__scrub.seek(ms)        — set all animations to given time
 *   window.__scrub.duration        — total duration (ms)
 *
 * Config shape:
 *   {
 *     selector: string,        // CSS selector
 *     keyframes: Keyframe[],   // Web Animations API keyframes
 *     duration: number,        // ms
 *     delay: number,           // ms (default 0)
 *   }[]
 *
 * Example:
 *   window.__scrub.setup([
 *     {
 *       selector: '.hero-wrapper',
 *       keyframes: [
 *         { opacity: '0', transform: 'translateY(43px)', filter: 'blur(16px)' },
 *         { opacity: '1', transform: 'translateY(0px)',  filter: 'blur(0px)'  },
 *       ],
 *       duration: 600,
 *       delay: 0,
 *     },
 *     {
 *       selector: '.subtitle',
 *       keyframes: [
 *         { opacity: '0', transform: 'translateY(80px)', filter: 'blur(16px)' },
 *         { opacity: '1', transform: 'translateY(0px)',  filter: 'blur(0px)'  },
 *       ],
 *       duration: 800,
 *       delay: 180,
 *     },
 *   ]);
 *   window.__scrub.seek(400);  // jump to t=400ms
 */

(function () {
  // Cancel ALL existing WAAPI on the page — including fill:forwards GC-retained ones
  // and any framework-driven animations (Framer Motion, GSAP WAAPI bridge, etc.).
  // This is intentional: scrubbing requires a clean slate. Side-effects like
  // UI flicker on cancel are expected — the page state will be restored by seek().
  // Uses document.getAnimations() when available (Chrome 84+, Firefox 75+, Safari 14+).
  // Falls back to per-element getAnimations() for older environments.
  function cancelAll() {
    var anims = document.getAnimations ? document.getAnimations() : null;
    if (anims) {
      for (var i = 0; i < anims.length; i++) anims[i].cancel();
      return;
    }
    var els = document.querySelectorAll('*');
    for (var i = 0; i < els.length; i++) {
      var elAnims = els[i].getAnimations ? els[i].getAnimations() : [];
      for (var j = 0; j < elAnims.length; j++) elAnims[j].cancel();
    }
  }

  // Clear all inline styles on an element (removes onfinish-committed opacity:1 etc.)
  function clearInlineStyles(el) {
    el.style.cssText = '';
  }

  var _anims = [];   // { anim: Animation, delay: number }
  var _totalDuration = 0;

  window.__scrub = {
    setup: function (configs) {
      // 1. Cancel everything
      cancelAll();

      // 2. Clear inline styles and create new paused animations
      _anims = [];
      _totalDuration = 0;

      for (var i = 0; i < configs.length; i++) {
        var cfg = configs[i];
        var delay = cfg.delay || 0;
        var duration = cfg.duration || 600;
        var total = delay + duration;
        if (total > _totalDuration) _totalDuration = total;

        var targets = document.querySelectorAll(cfg.selector);
        if (targets.length === 0) {
          console.warn('waapi-scrub: selector matched 0 elements:', cfg.selector);
        }
        for (var k = 0; k < targets.length; k++) {
          var el = targets[k];
          clearInlineStyles(el);

          var anim = el.animate(cfg.keyframes, {
            duration: duration,
            delay: delay,
            // fill:'both' shows the from-keyframe during the delay period (currentTime < delay)
            // and holds the to-keyframe after the animation ends.
            // NOTE: seek(0) will show the from-state even before the delay starts — this is correct
            // for scrubbing. If you need to see the pre-animation state, seek to a negative value
            // or read element styles before calling setup().
            fill: 'both',
            // NOTE: always extract easing from the live site — do not rely on this default.
            // Use css-extraction.md → transitionTimingFunction or animationTimingFunction.
            easing: cfg.easing || 'linear',
          });
          anim.pause();
          anim.currentTime = 0;

          _anims.push({ anim: anim, delay: delay, duration: duration });
        }
      }

      return 'scrub ready, totalDuration=' + _totalDuration + 'ms, animations=' + _anims.length;
    },

    seek: function (ms) {
      var clampedMs = Math.max(0, ms);
      for (var i = 0; i < _anims.length; i++) {
        var a = _anims[i].anim;
        // An animation in 'finished' state throws InvalidStateError on currentTime assignment.
        // Calling pause() first moves it back to 'paused' regardless of current state.
        if (a.playState !== 'paused') a.pause();
        a.currentTime = clampedMs;
      }
      return 'seeked to ' + clampedMs + 'ms';
    },

    get duration() {
      return _totalDuration;
    },
  };

  return 'waapi-scrub-inject loaded. Call window.__scrub.setup(configs) to begin.';
})()
