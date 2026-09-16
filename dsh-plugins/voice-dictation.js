/**
 * Voice Dictation Plugin for DeepSeek Harness (DSH)
 * 
 * Adds a microphone icon to the composer toolbar beside Workspace Write
 * and Plan mode to transcribe speech directly into the prompt box
 * using the browser's Web Speech API.
 */
return {
  name: 'voice-dictation',
  inject: ['slots'],
  apply: function(ctx) {
    var slots = ctx.get('slots');
    if (!slots) return;

    var css = [
      '.dsh-voice-btn {',
      '  min-width: 28px;',
      '  height: 28px;',
      '  color: var(--dsw-alias-label-secondary);',
      '  cursor: pointer;',
      '  background: transparent;',
      '  border: none;',
      '  border-radius: 999px;',
      '  outline: none;',
      '  align-items: center;',
      '  justify-content: center;',
      '  padding: 0 6px;',
      '  display: inline-flex;',
      '  transition: background 0.15s, color 0.15s, transform 0.1s;',
      '}',
      '.dsh-voice-btn:hover {',
      '  background: var(--dsw-alias-interactive-bg-hover);',
      '  color: var(--dsw-alias-label-primary);',
      '}',
      '.dsh-voice-btn:focus-visible {',
      '  box-shadow: 0 0 0 2px var(--dsw-alias-border-l3);',
      '}',
      '.dsh-voice-active {',
      '  background: var(--dsw-alias-state-error-primary, #ef4444) !important;',
      '  color: #ffffff !important;',
      '  animation: dsh-voice-pulse 1.5s infinite;',
      '}',
      '@keyframes dsh-voice-pulse {',
      '  0% { transform: scale(1); box-shadow: 0 0 0 0 rgba(239, 68, 68, 0.5); }',
      '  50% { transform: scale(1.05); box-shadow: 0 0 0 6px rgba(239, 68, 68, 0); }',
      '  100% { transform: scale(1); box-shadow: 0 0 0 0 rgba(239, 68, 68, 0); }',
      '}',
      '.dsh-voice-icon { display: flex; align-items: center; justify-content: center; }'
    ].join('\n');

    if (typeof styles !== 'undefined' && styles.insert) {
      styles.insert(css);
    }

    function VoiceDictationButton(props) {
      var listeningState = React.useState(false);
      var listening = listeningState[0];
      var setListening = listeningState[1];

      var recognitionRef = React.useRef(null);
      var baseDraftRef = React.useRef('');

      var inputState = props.useInput ? props.useInput(function(s) { return s; }) : null;
      var draft = inputState ? inputState.draft : '';

      React.useEffect(function() {
        return function() {
          if (recognitionRef.current) {
            try { recognitionRef.current.abort(); } catch (e) {}
          }
        };
      }, []);

      function toggleDictation() {
        var SpeechRec = typeof window !== 'undefined' && (window.SpeechRecognition || window.webkitSpeechRecognition);
        if (!SpeechRec) {
          alert('Speech Recognition is not supported by this browser. Please use Chrome, Edge, or Safari.');
          return;
        }

        if (listening) {
          if (recognitionRef.current) {
            try { recognitionRef.current.stop(); } catch (e) {}
          }
          setListening(false);
          return;
        }

        try {
          var rec = new SpeechRec();
          rec.continuous = true;
          rec.interimResults = true;
          rec.lang = (typeof navigator !== 'undefined' && navigator.language) || 'en-US';

          baseDraftRef.current = draft || '';

          rec.onstart = function() {
            setListening(true);
          };

          rec.onresult = function(event) {
            var fullTranscript = '';
            for (var i = 0; i < event.results.length; i++) {
              fullTranscript += event.results[i][0].transcript;
            }
            if (props.inputActions && props.inputActions.setDraft) {
              var base = baseDraftRef.current.trim();
              var combined = base.length > 0 ? base + ' ' + fullTranscript : fullTranscript;
              props.inputActions.setDraft(combined);
            }
          };

          rec.onerror = function(event) {
            console.error('Speech recognition error:', event.error);
            setListening(false);
          };

          rec.onend = function() {
            setListening(false);
          };

          recognitionRef.current = rec;
          rec.start();
        } catch (err) {
          console.error('Failed to start speech recognition:', err);
          setListening(false);
        }
      }

      var icon = React.createElement(
        'svg',
        { width: '16', height: '16', viewBox: '0 0 16 16', fill: 'none' },
        React.createElement('path', {
          d: 'M8 1.5C6.89543 1.5 6 2.39543 6 3.5V8.5C6 9.60457 6.89543 10.5 8 10.5C9.10457 10.5 10 9.60457 10 8.5V3.5C10 2.39543 9.10457 1.5 8 1.5Z',
          fill: 'currentColor'
        }),
        React.createElement('path', {
          d: 'M3.75 7.5C3.75 7.08579 3.41421 6.75 3 6.75C2.58579 6.75 2.25 7.08579 2.25 7.5C2.25 10.3204 4.31688 12.6631 7.025 12.9645V14.25H5.5C5.08579 14.25 4.75 14.5858 4.75 15C4.75 15.4142 5.08579 15.75 5.5 15.75H10.5C10.9142 15.75 11.25 15.4142 11.25 15C11.25 14.5858 10.9142 14.25 10.5 14.25H8.975V12.9645C11.6831 12.6631 13.75 10.3204 13.75 7.5C13.75 7.08579 13.4142 6.75 13 6.75C12.5858 6.75 12.25 7.08579 12.25 7.5C12.25 9.84721 10.3472 11.75 8 11.75C5.65279 11.75 3.75 9.84721 3.75 7.5Z',
          fill: 'currentColor'
        })
      );

      return React.createElement(
        'button',
        {
          type: 'button',
          className: 'dsh-voice-btn' + (listening ? ' dsh-voice-active' : ''),
          title: listening ? 'Listening... (click to stop)' : 'Dictate prompt (speech-to-text)',
          'aria-label': listening ? 'Stop voice dictation' : 'Start voice dictation',
          onClick: toggleDictation
        },
        React.createElement('span', { className: 'dsh-voice-icon', 'aria-hidden': 'true' }, icon)
      );
    }

    slots.inject('conversation.input.left', function() {
      return slots.register(
        {
          name: 'conversation.input.left',
          id: 'voice-dictation-control',
          order: 20,
          label: 'Voice Dictation'
        },
        VoiceDictationButton
      );
    });
  }
};
