/**
 * TFAWebApplication - Client-Side Scripts
 * Using jQuery & Bootstrap 5
 */

$(function () {
  'use strict';

  // 1. Initialize Bootstrap Tooltips
  var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
  tooltipTriggerList.map(function (tooltipTriggerEl) {
    return new bootstrap.Tooltip(tooltipTriggerEl);
  });

  // 2. Sidebar Navigation Items Click Handler (Matching Reference Image)
  $('.sidebar-nav-item').on('click', function (e) {
    e.preventDefault();
    $('.sidebar-nav-item').removeClass('active');
    $(this).addClass('active');

    var section = $(this).data('section');

    switch (section) {
      case 'dashboard':
        $('#tabDashboard').trigger('click');
        break;
      case 'users':
        var userModal = new bootstrap.Modal(document.getElementById('userProfileModal'));
        userModal.show();
        break;
      case 'settings':
        var settingsModal = new bootstrap.Modal(document.getElementById('settingsModal'));
        settingsModal.show();
        break;
      case 'notifications':
        var notifModal = new bootstrap.Modal(document.getElementById('notificationsModal'));
        notifModal.show();
        break;
      case 'security':
        var secModal = new bootstrap.Modal(document.getElementById('securityModal'));
        secModal.show();
        break;
      case 'products':
      case 'orders':
      case 'analytics':
      case 'sales':
        // Activate Dashboard view
        $('#tabDashboard').trigger('click');
        break;
      default:
        break;
    }
  });

  // 3. Workspace Tab Switching Handler (Dashboard <-> Home)
  $('.tfa-tab').on('click', function () {
    $('.tfa-tab').removeClass('active');
    $(this).addClass('active');

    var targetView = $(this).data('target');
    if (targetView === '#viewDashboard') {
      $('#viewDashboard').removeClass('d-none');
      $('#viewHome').addClass('d-none');
      $('#menuDashboard').addClass('active');
    } else if (targetView === '#viewHome') {
      $('#viewHome').removeClass('d-none');
      $('#viewDashboard').addClass('d-none');
    }
  });

  // 4. Global Keyboard Shortcuts (Ctrl + K for search modal)
  $(document).on('keydown', function (e) {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      var searchModalEl = document.getElementById('quickSearchModal');
      if (searchModalEl) {
        var searchModal = bootstrap.Modal.getOrCreateInstance(searchModalEl);
        searchModal.show();
        setTimeout(function () {
          $('#txtQuickSearch').focus();
        }, 300);
      }
    }
  });

  // 5. Quick Search Modal Real-time Filtering
  $('#txtQuickSearch').on('keyup', function () {
    var query = $(this).val().toLowerCase().trim();
    $('.tfa-search-result-item').each(function () {
      var text = $(this).text().toLowerCase();
      if (text.indexOf(query) > -1 || query === '') {
        $(this).removeClass('d-none');
      } else {
        $(this).addClass('d-none');
      }
    });

    var visibleItems = $('.tfa-search-result-item:not(.d-none)').length;
    if (visibleItems === 0) {
      $('#searchNoResults').removeClass('d-none');
    } else {
      $('#searchNoResults').addClass('d-none');
    }
  });

  // 6. Navbar Dropdowns Hover Support for Desktop
  if (window.matchMedia('(min-width: 992px)').matches) {
    $('.tfa-tier-green .dropdown').hover(
      function () {
        var $dropdown = $(this);
        $dropdown.find('.dropdown-menu').first().stop(true, true).slideDown(150);
        $dropdown.addClass('show');
      },
      function () {
        var $dropdown = $(this);
        $dropdown.find('.dropdown-menu').first().stop(true, true).slideUp(100);
        $dropdown.removeClass('show');
      }
    );
  }

  console.log('TFAWebApplication modern sidebar & dashboard scripts loaded.');
});
