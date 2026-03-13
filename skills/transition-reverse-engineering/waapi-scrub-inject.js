/**
 * waapi-scrub-inject.js
 *
 * Inject into a page after load to enable WAAPI time scrubbing.
 * Useful for page-load animations that complete before any screenshot is possible.
 *
 * Usage (agent-browser):
 *   agent-browser eval "$(cat waapi-scrub-inject.js)"
 *
 * WARNING: If keyframes use % units (e.g. translateX(-20%)), shell will expand %.
 * Use single quotes around the eval argument or store the script in a temp file:
 *   agent-browser eval "$(cat waapi-scrub-inject.js)"
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
  // Cancel all existing WAAPI on the page (including fill:forwards GC-retained ones)
  function cancelAll() {
    var els = document.querySelectorAll('*');
    for (var i = 0; i < els.length; i++) {
      var anims = els[i].getAnimations ? els[i].getAnimations() : [];
      for (var j = 0; j < anims.length; j++) {
        anims[j].cancel();
      }
    }
  }

  // Clear all inline styles on an element (removes onComplete-committed opacity:1 etc.)
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
        for (var k = 0; k < targets.length; k++) {
          var el = targets[k];
          clearInlineStyles(el);

          var anim = el.animate(cfg.keyframes, {
            duration: duration,
            delay: delay,
            fill: 'both',   // shows from-state at currentTime < delay
            easing: cfg.easing || 'ease',
          });
          anim.pause();
          anim.currentTime = 0;

          _anims.push({ anim: anim, delay: delay, duration: duration });
        }
      }

      return 'scrub ready, totalDuration=' + _totalDuration + 'ms, animations=' + _anims.length;
    },

    seek: function (ms) {
      for (var i = 0; i < _anims.length; i++) {
        _anims[i].anim.currentTime = ms;
      }
      return 'seeked to ' + ms + 'ms';
    },

    get duration() {
      return _totalDuration;
    },
  };

  return 'waapi-scrub-inject loaded. Call window.__scrub.setup(configs) to begin.';
})()
