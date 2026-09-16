/**
 * Token Availability Meter Plugin for DeepSeek Harness (DSH)
 * 
 * Displays a compact graphic on the composer tab beside Workspace Write
 * and Plan mode showing remaining model tokens as a percentage starting
 * from 100% and counting down with usage.
 * 
 * Includes interactive hover tooltip and click-to-open details popover.
 */
return {
  name: 'token-meter',
  inject: ['slots'],
  apply: function(ctx) {
    var slots = ctx.get('slots');
    if (!slots) return;

    var css = [
      '.dsh-token-stat-wrap { display: inline-flex; position: relative; align-items: center; }',
      '.dsh-token-stat-btn {',
      '  min-width: 0;',
      '  height: 28px;',
      '  color: var(--dsw-alias-label-secondary);',
      '  cursor: pointer;',
      '  background: transparent;',
      '  border: none;',
      '  border-radius: 24px;',
      '  outline: none;',
      '  align-items: center;',
      '  gap: 5px;',
      '  padding: 0 6px;',
      '  font-size: 12px;',
      '  font-weight: 500;',
      '  line-height: 20px;',
      '  display: inline-flex;',
      '  font-variant-numeric: tabular-nums;',
      '  transition: background 0.12s, color 0.12s;',
      '}',
      '.dsh-token-stat-btn:hover {',
      '  background: var(--dsw-alias-interactive-bg-hover);',
      '  color: var(--dsw-alias-label-primary);',
      '}',
      '.dsh-token-stat-btn:focus-visible {',
      '  box-shadow: 0 0 0 2px var(--dsw-alias-border-l3);',
      '}',
      '.dsh-token-stat-ring {',
      '  flex: none;',
      '  display: inline-flex;',
      '  align-items: center;',
      '  justify-content: center;',
      '}',
      '.dsh-token-stat-ring svg { display: block; }',
      '.dsh-token-stat-label { white-space: nowrap; letter-spacing: -0.01em; }',
      '.dsh-token-stat-backdrop {',
      '  position: fixed;',
      '  top: 0; left: 0; right: 0; bottom: 0;',
      '  z-index: 998;',
      '}',
      '.dsh-token-stat-popover {',
      '  position: absolute;',
      '  bottom: calc(100% + 8px);',
      '  left: 0;',
      '  width: 220px;',
      '  padding: 10px 12px;',
      '  background: var(--dsw-specific-menu, var(--dsw-alias-bg-overlay, #1e1e22));',
      '  border: 1px solid var(--dsw-alias-border-l1, rgba(255,255,255,0.12));',
      '  border-radius: 12px;',
      '  box-shadow: var(--dsw-elevation-prominent, 0 8px 24px rgba(0,0,0,0.35));',
      '  color: var(--dsw-alias-label-secondary);',
      '  font-size: 12px;',
      '  line-height: 18px;',
      '  z-index: 999;',
      '  cursor: default;',
      '  box-sizing: border-box;',
      '}',
      '.dsh-token-stat-pop-header {',
      '  display: flex;',
      '  justify-content: space-between;',
      '  align-items: center;',
      '  margin-bottom: 6px;',
      '}',
      '.dsh-token-stat-pop-title {',
      '  font-weight: 600;',
      '  font-size: 12px;',
      '  color: var(--dsw-alias-label-primary);',
      '}',
      '.dsh-token-stat-pop-val {',
      '  font-weight: 600;',
      '  font-size: 12px;',
      '  font-variant-numeric: tabular-nums;',
      '}',
      '.dsh-token-stat-bar-track {',
      '  width: 100%;',
      '  height: 4px;',
      '  background: var(--dsw-alias-interactive-bg-hover, rgba(255,255,255,0.1));',
      '  border-radius: 999px;',
      '  overflow: hidden;',
      '  margin-bottom: 8px;',
      '}',
      '.dsh-token-stat-bar-fill {',
      '  height: 100%;',
      '  border-radius: 999px;',
      '  transition: width 0.2s ease;',
      '}',
      '.dsh-token-stat-pop-rows {',
      '  margin: 0;',
      '  padding: 0;',
      '}',
      '.dsh-token-stat-pop-row {',
      '  display: flex;',
      '  justify-content: space-between;',
      '  align-items: center;',
      '  padding: 2px 0;',
      '  font-size: 11px;',
      '}',
      '.dsh-token-stat-pop-row dt {',
      '  color: var(--dsw-alias-label-secondary);',
      '  margin: 0;',
      '}',
      '.dsh-token-stat-pop-row dd {',
      '  color: var(--dsw-alias-label-primary);',
      '  font-variant-numeric: tabular-nums;',
      '  font-weight: 500;',
      '  margin: 0;',
      '}'
    ].join('\n');

    if (typeof styles !== 'undefined' && styles.insert) {
      styles.insert(css);
    }

    function TokenMeter(props) {
      var pressure = props.useProjection ? props.useProjection('contextPressure') : null;
      var tokenUsage = props.useProjection ? props.useProjection('tokenUsage') : null;
      var openState = React.useState(false);
      var open = openState[0];
      var setOpen = openState[1];

      var contextWindow = (pressure && pressure.contextWindow) ? pressure.contextWindow : 1048576;
      var usedTokens = 0;
      if (pressure && (pressure.projectedTokens !== undefined || pressure.pressureTokens !== undefined)) {
        usedTokens = pressure.projectedTokens !== undefined ? pressure.projectedTokens : pressure.pressureTokens;
      } else if (tokenUsage && tokenUsage.totals) {
        usedTokens = (tokenUsage.totals.uncachedInputTokens || 0) + (tokenUsage.totals.outputTokens || 0);
      }

      var usedPercent = pressure && pressure.contextWindow
        ? Math.min(100, Math.max(0, Math.round((usedTokens / pressure.contextWindow) * 100)))
        : (usedTokens > 0 ? Math.min(100, Math.round((usedTokens / contextWindow) * 100)) : 0);

      var remainingPercent = Math.max(0, 100 - usedPercent);
      var remainingTokens = Math.max(0, contextWindow - usedTokens);

      var RADIUS = 6;
      var CIRCUMFERENCE = 2 * Math.PI * RADIUS;
      var strokeDashoffset = CIRCUMFERENCE * (1 - remainingPercent / 100);

      var meterColor = 'var(--dsw-alias-label-secondary)';
      if (remainingPercent <= 10) {
        meterColor = 'var(--dsw-alias-state-error-primary, #ef4444)';
      } else if (remainingPercent <= 25) {
        meterColor = 'var(--dsw-alias-state-warn-primary, #f59e0b)';
      }

      function formatTokens(v) {
        if (v === undefined || v === null) return '0';
        if (v < 1000) return String(v);
        if (v < 1000000) return (v / 1000).toFixed(v >= 10000 ? 0 : 1) + 'k';
        return (v / 1000000).toFixed(v >= 10000000 ? 0 : 1) + 'M';
      }

      var children = [
        React.createElement(
          'button',
          {
            key: 'btn',
            type: 'button',
            className: 'dsh-token-stat-btn',
            title: remainingPercent + '% tokens remaining (~' + formatTokens(remainingTokens) + ' / ' + formatTokens(contextWindow) + ')',
            'aria-label': 'Remaining tokens: ' + remainingPercent + '%',
            onClick: function() { setOpen(!open); }
          },
          React.createElement(
            'span',
            { className: 'dsh-token-stat-ring', 'aria-hidden': 'true' },
            React.createElement(
              'svg',
              { width: '16', height: '16', viewBox: '0 0 16 16' },
              React.createElement('circle', {
                cx: '8',
                cy: '8',
                r: String(RADIUS),
                fill: 'none',
                stroke: 'var(--dsw-alias-border-l3, rgba(255,255,255,0.15))',
                strokeWidth: '2'
              }),
              React.createElement('circle', {
                cx: '8',
                cy: '8',
                r: String(RADIUS),
                fill: 'none',
                stroke: meterColor,
                strokeWidth: '2',
                strokeLinecap: 'round',
                strokeDasharray: String(CIRCUMFERENCE),
                strokeDashoffset: String(strokeDashoffset),
                transform: 'rotate(-90 8 8)'
              })
            )
          ),
          React.createElement(
            'span',
            { className: 'dsh-token-stat-label' },
            remainingPercent + '%'
          )
        )
      ];

      if (open) {
        children.push(
          React.createElement('div', {
            key: 'backdrop',
            className: 'dsh-token-stat-backdrop',
            onClick: function(e) {
              e.stopPropagation();
              setOpen(false);
            }
          }),
          React.createElement(
            'div',
            {
              key: 'popover',
              className: 'dsh-token-stat-popover',
              role: 'dialog',
              'aria-label': 'Token Details'
            },
            React.createElement(
              'div',
              { className: 'dsh-token-stat-pop-header' },
              React.createElement('span', { className: 'dsh-token-stat-pop-title' }, 'Tokens Available'),
              React.createElement('span', { className: 'dsh-token-stat-pop-val', style: { color: meterColor } }, remainingPercent + '%')
            ),
            React.createElement(
              'div',
              { className: 'dsh-token-stat-bar-track' },
              React.createElement('div', {
                className: 'dsh-token-stat-bar-fill',
                style: {
                  width: remainingPercent + '%',
                  backgroundColor: meterColor
                }
              })
            ),
            React.createElement(
              'dl',
              { className: 'dsh-token-stat-pop-rows' },
              React.createElement(
                'div',
                { className: 'dsh-token-stat-pop-row' },
                React.createElement('dt', null, 'Available'),
                React.createElement('dd', null, '~' + formatTokens(remainingTokens))
              ),
              React.createElement(
                'div',
                { className: 'dsh-token-stat-pop-row' },
                React.createElement('dt', null, 'Used (' + usedPercent + '%)'),
                React.createElement('dd', null, '~' + formatTokens(usedTokens))
              ),
              React.createElement(
                'div',
                { className: 'dsh-token-stat-pop-row' },
                React.createElement('dt', null, 'Model Capacity'),
                React.createElement('dd', null, '~' + formatTokens(contextWindow))
              )
            )
          )
        );
      }

      return React.createElement('div', { className: 'dsh-token-stat-wrap' }, children);
    }

    slots.inject('conversation.input.left', function() {
      return slots.register(
        {
          name: 'conversation.input.left',
          id: 'token-subscription-meter',
          order: 10,
          label: 'Available Tokens'
        },
        TokenMeter
      );
    });
  }
};
