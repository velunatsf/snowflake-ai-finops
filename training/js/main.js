/**
 * AI for FinOps Training - Main JavaScript
 * FinOps for Snowflake AI · Snowflake AI FinOps Training
 * 
 * Features:
 * - Copy code functionality for all code blocks
 * - Progress tracking across modules
 * - Checkpoint reveal functionality
 * - Token cost calculator
 * - Navigation state management
 */

(function() {
  'use strict';

  // ─── Constants ────────────────────────────────────────────────────────────
  const MODULES = [
    { id: '01', title: 'AI Token Economy', file: '01-ai-token-economy.html' },
    { id: '02', title: 'Cortex AI Capabilities', file: '02-cortex-ai-capabilities.html' },
    { id: '03', title: 'Environment Setup', file: '03-environment-setup.html' },
    { id: '04', title: 'CoCo Setup', file: '04-cortex-code-setup.html' },
    { id: '05', title: 'AI SQL Hands-On', file: '05-ai-sql-hands-on.html' },
    { id: '06', title: 'Token Usage Tracking', file: '06-token-usage-tracking.html' },
    { id: '07', title: 'What\'s New', file: '07-ai-credits-transition.html' },
    { id: '08', title: 'Streamlit Dashboard', file: '08-streamlit-dashboard.html' },
    { id: '09', title: 'Closing Note', file: '09-closing-note.html' }
  ];

  const STORAGE_KEY = 'aifinops_progress';

  // ─── Copy Code Functionality ──────────────────────────────────────────────
  function initCopyButtons() {
    const copyButtons = document.querySelectorAll('.copy-btn');
    
    copyButtons.forEach(btn => {
      btn.addEventListener('click', async function() {
        const codeBlock = this.closest('.code-block');
        const codeContent = codeBlock.querySelector('pre');
        
        if (!codeContent) return;
        
        const text = codeContent.textContent;
        
        try {
          await navigator.clipboard.writeText(text);
          
          // Visual feedback
          const originalHTML = this.innerHTML;
          this.innerHTML = '<span>Copied!</span>';
          this.classList.add('copied');
          
          setTimeout(() => {
            this.innerHTML = originalHTML;
            this.classList.remove('copied');
          }, 2000);
        } catch (err) {
          console.error('Failed to copy:', err);
          
          // Fallback for older browsers
          const textarea = document.createElement('textarea');
          textarea.value = text;
          textarea.style.position = 'fixed';
          textarea.style.opacity = '0';
          document.body.appendChild(textarea);
          textarea.select();
          
          try {
            document.execCommand('copy');
            this.innerHTML = '<span>Copied!</span>';
            this.classList.add('copied');
            
            setTimeout(() => {
              this.innerHTML = '<span>Copy</span>';
              this.classList.remove('copied');
            }, 2000);
          } catch (e) {
            console.error('Fallback copy failed:', e);
          }
          
          document.body.removeChild(textarea);
        }
      });
    });
  }

  // ─── Progress Tracking ────────────────────────────────────────────────────
  function getProgress() {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      return stored ? JSON.parse(stored) : { completed: [], current: null };
    } catch (e) {
      return { completed: [], current: null };
    }
  }

  function saveProgress(progress) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(progress));
    } catch (e) {
      console.warn('Could not save progress:', e);
    }
  }

  function markModuleVisited(moduleId) {
    const progress = getProgress();
    progress.current = moduleId;
    if (!progress.completed.includes(moduleId)) {
      progress.completed.push(moduleId);
    }
    saveProgress(progress);
    updateProgressUI();
  }

  function updateProgressUI() {
    const progress = getProgress();
    const progressBar = document.querySelector('.progress-bar-fill');
    const progressText = document.querySelector('.progress-text');
    
    if (progressBar) {
      const percentage = (progress.completed.length / MODULES.length) * 100;
      progressBar.style.width = `${percentage}%`;
    }
    
    if (progressText) {
      progressText.textContent = `${progress.completed.length} of ${MODULES.length} modules`;
    }

    // Update nav links
    const navLinks = document.querySelectorAll('.nav-link');
    navLinks.forEach(link => {
      const moduleId = link.dataset.module;
      if (moduleId && progress.completed.includes(moduleId)) {
        link.classList.add('visited');
      }
    });
  }

  function getCurrentModuleId() {
    const path = window.location.pathname;
    const match = path.match(/(\d{2})-/);
    return match ? match[1] : null;
  }

  // ─── Checkpoint Reveal ────────────────────────────────────────────────────
  function initCheckpoints() {
    const revealButtons = document.querySelectorAll('.reveal-btn');
    
    revealButtons.forEach(btn => {
      btn.addEventListener('click', function() {
        const question = this.closest('.checkpoint-question');
        const answer = question.querySelector('.checkpoint-answer');
        
        if (answer) {
          answer.classList.toggle('show');
          this.textContent = answer.classList.contains('show') 
            ? 'Hide Answer' 
            : 'Reveal Answer';
        }
      });
    });
  }

  // ─── Token Cost Calculator ────────────────────────────────────────────────
  function initCalculator() {
    const calculator = document.getElementById('token-calculator');
    if (!calculator) return;

    // Model rates (credits per 1M tokens) - from Snowflake pricing
    const modelRates = {
      'mistral-7b': { input: 0.12, output: 0.12 },
      'llama3-8b': { input: 0.19, output: 0.19 },
      'mixtral-8x7b': { input: 0.22, output: 0.22 },
      'llama3-70b': { input: 1.21, output: 1.21 },
      'llama3.1-70b': { input: 1.21, output: 1.21 },
      'llama3.1-405b': { input: 3.00, output: 3.00 },
      'mistral-large': { input: 5.10, output: 5.10 },
      'claude-3-5-sonnet': { input: 1.50, output: 7.50 },
      'claude-3-haiku': { input: 0.25, output: 1.25 },
      'reka-flash': { input: 0.45, output: 0.45 },
      'snowflake-arctic': { input: 0.84, output: 0.84 }
    };

    const promptSlider = document.getElementById('calc-prompt-tokens');
    const responseSlider = document.getElementById('calc-response-tokens');
    const callsSlider = document.getElementById('calc-calls-per-day');
    const modelSelect = document.getElementById('calc-model');

    const promptValue = document.getElementById('prompt-value');
    const responseValue = document.getElementById('response-value');
    const callsValue = document.getElementById('calls-value');

    const resultPerCall = document.getElementById('result-per-call');
    const resultDaily = document.getElementById('result-daily');
    const resultMonthly = document.getElementById('result-monthly');
    const resultDollars = document.getElementById('result-dollars');

    function updateCalculator() {
      const promptTokens = parseInt(promptSlider.value) || 0;
      const responseTokens = parseInt(responseSlider.value) || 0;
      const callsPerDay = parseInt(callsSlider.value) || 0;
      const model = modelSelect.value;

      // Update displayed values
      if (promptValue) promptValue.textContent = promptTokens.toLocaleString();
      if (responseValue) responseValue.textContent = responseTokens.toLocaleString();
      if (callsValue) callsValue.textContent = callsPerDay.toLocaleString();

      // Calculate costs
      const rates = modelRates[model] || { input: 0.5, output: 0.5 };
      const inputCredits = (promptTokens / 1000000) * rates.input;
      const outputCredits = (responseTokens / 1000000) * rates.output;
      const creditsPerCall = inputCredits + outputCredits;
      const dailyCredits = creditsPerCall * callsPerDay;
      const monthlyCredits = dailyCredits * 30;
      const monthlyDollars = monthlyCredits * 3; // $3 per credit estimate

      // Update results
      if (resultPerCall) resultPerCall.textContent = creditsPerCall.toFixed(6);
      if (resultDaily) resultDaily.textContent = dailyCredits.toFixed(4);
      if (resultMonthly) resultMonthly.textContent = monthlyCredits.toFixed(2);
      if (resultDollars) resultDollars.textContent = '$' + monthlyDollars.toFixed(2);
    }

    // Add event listeners
    [promptSlider, responseSlider, callsSlider, modelSelect].forEach(el => {
      if (el) {
        el.addEventListener('input', updateCalculator);
        el.addEventListener('change', updateCalculator);
      }
    });

    // Initial calculation
    updateCalculator();
  }

  // ─── Smooth Scroll for Anchor Links ───────────────────────────────────────
  function initSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
      anchor.addEventListener('click', function(e) {
        const targetId = this.getAttribute('href');
        if (targetId === '#') return;
        
        const target = document.querySelector(targetId);
        if (target) {
          e.preventDefault();
          target.scrollIntoView({
            behavior: 'smooth',
            block: 'start'
          });
        }
      });
    });
  }

  // ─── Keyboard Navigation ──────────────────────────────────────────────────
  function initKeyboardNav() {
    document.addEventListener('keydown', function(e) {
      // Only if not in an input field
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
        return;
      }

      const currentModule = getCurrentModuleId();
      const currentIndex = MODULES.findIndex(m => m.id === currentModule);

      if (e.key === 'ArrowRight' && currentIndex < MODULES.length - 1) {
        // Go to next module
        const nextModule = MODULES[currentIndex + 1];
        window.location.href = nextModule.file;
      } else if (e.key === 'ArrowLeft' && currentIndex > 0) {
        // Go to previous module
        const prevModule = MODULES[currentIndex - 1];
        window.location.href = prevModule.file;
      }
    });
  }

  // ─── Active Nav Highlighting ──────────────────────────────────────────────
  function initNavHighlight() {
    const currentModule = getCurrentModuleId();
    const navLinks = document.querySelectorAll('.nav-link');
    
    navLinks.forEach(link => {
      const moduleId = link.dataset.module;
      if (moduleId === currentModule) {
        link.classList.add('active');
      }
    });
  }

  // ─── Code Syntax Highlighting (Basic) ─────────────────────────────────────
  function highlightCode() {
    document.querySelectorAll('.code-content pre').forEach(pre => {
      let html = pre.innerHTML;
      
      // SQL keywords
      const sqlKeywords = /\b(SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AND|OR|AS|CREATE|DROP|ALTER|INSERT|UPDATE|DELETE|INTO|VALUES|SET|WITH|LIMIT|ORDER|BY|GROUP|HAVING|CASE|WHEN|THEN|ELSE|END|UNION|ALL|DISTINCT|NOT|IN|IS|NULL|TRUE|FALSE|LIKE|ILIKE|BETWEEN|EXISTS|GRANT|REVOKE|TO|ROLE|DATABASE|SCHEMA|TABLE|VIEW|WAREHOUSE|RESOURCE|MONITOR|TRIGGERS|PERCENT|DO|NOTIFY|SUSPEND_IMMEDIATE|DATEADD|CURRENT_TIMESTAMP|CURRENT_USER|COUNT|SUM|AVG|MIN|MAX|ROUND|CONCAT|LEFT|RIGHT|UPPER|LOWER|REGEXP_SUBSTR|NULLIF|DATE_TRUNC)\b/gi;
      
      // Snowflake specific
      const snowflakeKeywords = /\b(SNOWFLAKE\.CORTEX\.\w+|SNOWFLAKE\.ACCOUNT_USAGE\.\w+|CORTEX_USER)\b/gi;
      
      // Strings
      const strings = /('[^']*')/g;
      
      // Numbers
      const numbers = /\b(\d+\.?\d*)\b/g;
      
      // Comments
      const comments = /(--.*$)/gm;

      // Apply highlighting
      html = html.replace(comments, '<span class="comment">$1</span>');
      html = html.replace(strings, '<span class="string">$1</span>');
      html = html.replace(sqlKeywords, '<span class="keyword">$1</span>');
      html = html.replace(snowflakeKeywords, '<span class="function">$1</span>');
      // Note: number highlighting can interfere with other patterns, be careful
      
      pre.innerHTML = html;
    });
  }

  // ─── Initialize ───────────────────────────────────────────────────────────
  function init() {
    // Mark current module as visited
    const currentModule = getCurrentModuleId();
    if (currentModule) {
      markModuleVisited(currentModule);
    }

    // Initialize all features
    initCopyButtons();
    initCheckpoints();
    initCalculator();
    initSmoothScroll();
    initKeyboardNav();
    initNavHighlight();
    updateProgressUI();
    
    // Optional: syntax highlighting
    // highlightCode();

    console.log('AI for FinOps Training initialized');
  }

  // Run on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // Expose utility functions globally for inline use
  window.AIFinOpsTraining = {
    getProgress,
    markModuleVisited,
    MODULES
  };

})();
