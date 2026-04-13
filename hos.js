// DOT Hours of Service projector for property-carrying CMV drivers.
// Implements the FMCSA rules in effect as of 2026:
//
//   - Max 11 hours driving after 10 consecutive hours off duty
//   - Max 14 hours on-duty window after 10 consecutive hours off duty
//     (the 14h clock does NOT pause for breaks in the current rule)
//   - Required 30-min break after 8 consecutive hours of driving
//   - Weekly cap: 60h / 7 days  OR  70h / 8 days (driver's elected schedule)
//   - Required 10 consecutive hours off-duty to reset daily clocks
//
// Given a start time and a total driving duration, this projects the
// sequence of drive / break / rest segments and returns the delivery ETA
// along with any rule violations.
//
// Source: https://www.fmcsa.dot.gov/regulations/hours-service/summary-hours-service-regulations

const MAX_DRIVE_PER_DAY_SEC     = 11 * 3600;
const MAX_ONDUTY_WINDOW_SEC     = 14 * 3600;
const MAX_CONSECUTIVE_DRIVE_SEC =  8 * 3600;
const BREAK_DURATION_SEC        =  30 * 60;
const REQUIRED_REST_SEC         = 10 * 3600;
const WEEKLY_CAP_HOURS = { '60/7': 60, '70/8': 70 };

/**
 * Project a delivery schedule under FMCSA HOS rules.
 *
 * @param {Object} opts
 * @param {string|Date} opts.startTime            ISO string or Date — when the driver starts the drive
 * @param {number}      opts.drivingDurationSec   Total required driving seconds (ie. route duration)
 * @param {number}      [opts.cumulativeWeekHoursBeforeStart=0]  Hours already worked in the current 7/8-day window
 * @param {'60/7'|'70/8'} [opts.schedule='70/8']  Driver's elected weekly limit
 * @returns {{
 *   segments: Array<{ type: 'drive'|'break'|'rest', start: string, end: string, durationSec: number, reason?: string, cumulativeDriveHours?: number }>,
 *   deliveryEta: string,
 *   totalElapsedSec: number,
 *   drivingSec: number,
 *   breakSec: number,
 *   restSec: number,
 *   violations: Array<{ type: string, message: string, atSegment: number }>,
 *   weekHoursAtEnd: number,
 * }}
 */
function projectDelivery(opts) {
  const startMs = (opts.startTime instanceof Date ? opts.startTime : new Date(opts.startTime)).getTime();
  const totalDriveSec = Math.max(0, Math.floor(opts.drivingDurationSec || 0));
  const schedule = opts.schedule && WEEKLY_CAP_HOURS[opts.schedule] ? opts.schedule : '70/8';
  const weeklyCapSec = WEEKLY_CAP_HOURS[schedule] * 3600;
  let weekSecUsed = Math.max(0, (opts.cumulativeWeekHoursBeforeStart || 0) * 3600);

  const segments = [];
  const violations = [];

  if (totalDriveSec === 0) {
    return {
      segments: [],
      deliveryEta: new Date(startMs).toISOString(),
      totalElapsedSec: 0,
      drivingSec: 0,
      breakSec: 0,
      restSec: 0,
      violations: [],
      weekHoursAtEnd: weekSecUsed / 3600,
    };
  }

  // Running clocks (all in seconds unless noted)
  let now                  = startMs;
  let remaining            = totalDriveSec;
  let consecutiveDrive     = 0;       // reset by 30-min break OR 10-h rest
  let dailyDrive           = 0;       // reset by 10-h rest
  let dutyWindowStart      = startMs; // 14-h clock anchor, reset by 10-h rest

  // Safety valve: don't loop forever
  let iterations = 0;
  const MAX_ITER = 50;

  while (remaining > 0 && iterations++ < MAX_ITER) {
    // How much runway we have before each mandatory stop
    const untilBreak    = MAX_CONSECUTIVE_DRIVE_SEC - consecutiveDrive;
    const untilDailyMax = MAX_DRIVE_PER_DAY_SEC     - dailyDrive;
    const untilWindowMax= MAX_ONDUTY_WINDOW_SEC     - Math.floor((now - dutyWindowStart) / 1000);
    const untilWeeklyCap= weeklyCapSec              - weekSecUsed;

    // Pick the tightest constraint vs what's left to drive
    const driveFor = Math.max(0, Math.min(remaining, untilBreak, untilDailyMax, untilWindowMax, untilWeeklyCap));

    if (driveFor <= 0) {
      // Can't drive any more right now — figure out why and insert the appropriate rest
      if (untilWeeklyCap <= 0) {
        violations.push({
          type: 'weekly-cap',
          message: `Driver hits the ${schedule} weekly cap (${WEEKLY_CAP_HOURS[schedule]}h) before this route completes. A 34-hour restart will be required.`,
          atSegment: segments.length,
        });
        // Project a 34-hour restart so the ETA still has meaning
        const restartEnd = now + 34 * 3600 * 1000;
        segments.push({
          type: 'rest',
          start: new Date(now).toISOString(),
          end: new Date(restartEnd).toISOString(),
          durationSec: 34 * 3600,
          reason: '34-hour weekly restart (weekly cap hit)',
        });
        now = restartEnd;
        weekSecUsed = 0;           // the 34-h restart resets the week
        dailyDrive = 0;
        consecutiveDrive = 0;
        dutyWindowStart = now;
        continue;
      }
      if (untilDailyMax <= 0 || untilWindowMax <= 0) {
        // 10-hour rest reset
        const restEnd = now + REQUIRED_REST_SEC * 1000;
        segments.push({
          type: 'rest',
          start: new Date(now).toISOString(),
          end: new Date(restEnd).toISOString(),
          durationSec: REQUIRED_REST_SEC,
          reason: untilDailyMax <= 0
            ? '10-hour rest (11-hour daily driving max reached)'
            : '10-hour rest (14-hour on-duty window exhausted)',
        });
        now = restEnd;
        dailyDrive = 0;
        consecutiveDrive = 0;
        dutyWindowStart = now;
        continue;
      }
      // Only a 30-min break is needed
      const breakEnd = now + BREAK_DURATION_SEC * 1000;
      segments.push({
        type: 'break',
        start: new Date(now).toISOString(),
        end: new Date(breakEnd).toISOString(),
        durationSec: BREAK_DURATION_SEC,
        reason: '30-minute break (8h consecutive driving)',
      });
      now = breakEnd;
      consecutiveDrive = 0;
      continue;
    }

    // Add the drive segment
    const driveEnd = now + driveFor * 1000;
    segments.push({
      type: 'drive',
      start: new Date(now).toISOString(),
      end: new Date(driveEnd).toISOString(),
      durationSec: driveFor,
      cumulativeDriveHours: (dailyDrive + driveFor) / 3600,
    });
    now = driveEnd;
    remaining          -= driveFor;
    consecutiveDrive   += driveFor;
    dailyDrive         += driveFor;
    weekSecUsed        += driveFor;
  }

  if (remaining > 0) {
    violations.push({
      type: 'unresolvable',
      message: `Projection aborted after ${MAX_ITER} segments — route may be infeasible under HOS rules without manual adjustments.`,
      atSegment: segments.length,
    });
  }

  const totalElapsed = Math.floor((now - startMs) / 1000);
  const drivingSec = segments.filter(s => s.type === 'drive').reduce((t, s) => t + s.durationSec, 0);
  const breakSec   = segments.filter(s => s.type === 'break').reduce((t, s) => t + s.durationSec, 0);
  const restSec    = segments.filter(s => s.type === 'rest').reduce((t, s) => t + s.durationSec, 0);

  return {
    segments,
    deliveryEta: new Date(now).toISOString(),
    totalElapsedSec: totalElapsed,
    drivingSec, breakSec, restSec,
    violations,
    weekHoursAtEnd: weekSecUsed / 3600,
  };
}

module.exports = { projectDelivery };
