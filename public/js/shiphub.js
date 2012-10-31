// main javascript for shiphub
var DEPLOY_LOCKED_DELAY = 2000;

// update a lock status
$.fn.shLock = function(locked) {
  var $lockStatus = $(this).closest('.well').find('.remote-deploy');
  if (locked) {
    $lockStatus.html('<span class="badge badge-important">Locked</span>');
  }
  else {
    $lockStatus.html('<span class="badge badge-success">Ready</span>');
  }
}

// update an output message
$.fn.shOut = function(message, isDone) {
  var $out = $(this).closest('.well').find('.deploy-output');
  if (message && isDone) {
    $('.deploy-output-label', $out).html('Last Deploy');
    message += '\n<b class="complete">&gt; finished!</b>';
    $('pre', $out).html(message);
    $out.show();
    $('pre', $out).scrollTop($('pre', $out)[0].scrollHeight);
  }
  else if (message) {
    $('.deploy-output-label', $out).html('Deploy Output');
    message += '\n<b class="cursor">&gt; in progress</b>';
    $('pre', $out).html(message);
    $out.show();
    $('pre', $out).scrollTop($('pre', $out)[0].scrollHeight);
  }
  else {
    $out.delay(5000).hide(500);
  }
}

// disable an instance
$.fn.shDisable = function(isDisabled) {
  if (isDisabled) {
    $(this).closest('.well').addClass('disabled');
    $(this).closest('.well').find('.btn').addClass('disabled');
  }
  else {
    $(this).closest('.well').removeClass('disabled');
    $(this).closest('.well').find('.btn').removeClass('disabled');
  }
}

// check if instance is disabled
$.fn.shDisabled = function() {
  $(this).closest('.well').hasClass('disabled');
}

// helper to poll for remote status changes
var checkSite = function($well) {
  var checkUrl = $well.find('.remote-deploy').first().attr('data-url');
  $.ajax({
    type: 'GET',
    url: checkUrl,
    success: function(data, text, jqXHR) {
      if (data.previous) {
        $well.shOut(data.previous, true);
      }
      else if (data.progress) {
        $well.shOut(data.progress);
      }

      $well.shLock(data.locked);
      $well.shDisable(data.locked);
      if (data.locked && $well.doPolling) {
        setTimeout(function() {checkSite($well);}, DEPLOY_LOCKED_DELAY);
      }
      else {
        $well.doPolling = false;
      }
    },
    error: function(jqXHR, text, err) {
      alert('Error - ' + text);
      console.error('Error', jqXHR, text, err);
    }
  });
}

// start/stop polling for an instance
$.fn.shPoll = function(isPolling) {
  $well = $(this).closest('.well');
  $well.doPolling = isPolling;
  if (isPolling) checkSite($well);
}

// let's go!
$(document).ready(function() {

  // when a shiphub action is clicked
  $('a.shaction').click(function(e) {
    e.preventDefault();
    var $el = $(this);

    // disabled
    if ($el.shDisabled()) return;

    // confirm
    var name = $el.html();
    var inst = $el.closest('.well').find('.site-name').html();
    var type = $el.hasClass('branch') ? 'branch' : 'pull request';
    if (!window.confirm('Deploy '+type+' "'+name+'" to '+inst+'?')) return;

    // ask server to deploy
    $.ajax({
      type: 'POST',
      url: $el.attr('href'),
      success: function(data, text, jqXHR) {
        if (data.success) {
          $el.shLock(true);
          $el.shDisable(true);
          $el.shOut(data.progress);
          $el.shPoll(true);
        }
        else {
          alert('Remote error - ' + data.message);
          console.error('Remote deploy error', data);
        }
      },
      error: function(jqXHR, text, err) {
        alert('Error - ' + err);
        console.error('Deploy error', jqXHR, text, err);
      }
    });
  });

  // do a single site-status check
  $('.remote-deploy').each(function(num, target) {
    checkSite($(target).closest('.well'));
  });

});
