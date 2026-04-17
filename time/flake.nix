{
  description = ''
    Usage
      {
        inputs.timestamp.url = "github:you/timestamp-flake";
        # or for local development:
        # inputs.timestamp.url = "path:/home/you/src/timestamp-flake";

        outputs = { self, nixpkgs, timestamp }: {
          someAttr = let
            now = timestamp.lib.fromTimestamp builtins.currentTime;
          in now.iso8601;
          # e.g. now.iso8601 => "2026-04-17T09:42:11Z"
          # e.g. now.human   => "Friday, April 17, 2026"
        };
      }
      The consumer writes timestamp.lib.fromTimestamp because that corresponds to the path exposed: outputs.lib.fromTimestamp.
      Test with nix eval .#lib.fromTimestamp --apply 'f: (f 0).iso8601'
  '';
  # outputs is a function. Its arguments are self (a reference to the flake
  # itself) plus one argument per entry in inputs. Since you have no inputs, the
  # signature is just { self }. You can also write { self, ... } if you want to
  # be permissive about extra arguments Nix might pass.
  # lib is a convention, not a requirement. Flakes have a loose schema —
  # packages, devShells, nixosModules, lib, etc. — but lib in particular is
  # unchecked and can hold anything. Nixpkgs itself exposes its library as
  # nixpkgs.lib, which is why this naming is familiar to Nix users.
  # No system scoping needed. Things like packages must be keyed by system
  # (packages.x86_64-linux.foo) because they produce build artifacts. Pure Nix
  # functions are platform-independent, so lib sits at the top level.
  outputs =
    { self, ... }:
    let
      fromTimestamp =
        timestamp:
        let
          mod = a: b: a - (a / b) * b;

          isLeap = y: (mod y 4 == 0 && mod y 100 != 0) || mod y 400 == 0;

          daysInMonth =
            y: m:
            let
              base = builtins.elemAt [
                31
                28
                31
                30
                31
                30
                31
                31
                30
                31
                30
                31
              ] (m - 1);
            in
            if m == 2 && isLeap y then 29 else base;

          monthNames = [
            "January"
            "February"
            "March"
            "April"
            "May"
            "June"
            "July"
            "August"
            "September"
            "October"
            "November"
            "December"
          ];
          weekdayNames = [
            "Sunday"
            "Monday"
            "Tuesday"
            "Wednesday"
            "Thursday"
            "Friday"
            "Saturday"
          ];

          second = mod timestamp 60;
          minute = mod (timestamp / 60) 60;
          hour = mod (timestamp / 3600) 24;
          totalDays = timestamp / 86400;

          # 1970-01-01 was a Thursday (index 4, Sunday = 0)
          weekday = mod (totalDays + 4) 7;

          stepYear =
            acc:
            let
              dy = if isLeap acc.year then 366 else 365;
            in
            if acc.days < dy then
              acc
            else
              stepYear {
                year = acc.year + 1;
                days = acc.days - dy;
              };
          y = stepYear {
            year = 1970;
            days = totalDays;
          };

          stepMonth =
            acc:
            let
              dm = daysInMonth y.year acc.month;
            in
            if acc.days < dm then
              acc
            else
              stepMonth {
                month = acc.month + 1;
                days = acc.days - dm;
              };
          m = stepMonth {
            month = 1;
            days = y.days;
          };

          year = y.year;
          month = m.month;
          day = m.days + 1;
          dayOfYear = y.days + 1;

          pad2 = n: if n < 10 then "0${toString n}" else toString n;
          pad4 =
            n:
            if n < 10 then
              "000${toString n}"
            else if n < 100 then
              "00${toString n}"
            else if n < 1000 then
              "0${toString n}"
            else
              toString n;

          hour12 =
            let
              h = mod hour 12;
            in
            if h == 0 then 12 else h;
        in
        rec {
          # raw numeric components
          inherit
            timestamp
            year
            month
            day
            hour
            minute
            second
            weekday
            dayOfYear
            ;

          # named forms
          monthName = builtins.elemAt monthNames (month - 1);
          monthNameShort = builtins.substring 0 3 monthName;
          weekdayName = builtins.elemAt weekdayNames weekday;
          weekdayNameShort = builtins.substring 0 3 weekdayName;

          # 12-hour clock
          inherit hour12;
          meridiem = if hour < 12 then "AM" else "PM";

          # zero-padded strings
          YYYY = pad4 year;
          MM = pad2 month;
          DD = pad2 day;
          hh = pad2 hour;
          mm = pad2 minute;
          ss = pad2 second;

          # common formats
          date = "${YYYY}-${MM}-${DD}";
          time = "${hh}:${mm}:${ss}";
          iso8601 = "${date}T${time}Z";
          rfc3339 = iso8601;

          # human readable
          human = "${weekdayName}, ${monthName} ${toString day}, ${toString year}";
          short = "${weekdayNameShort} ${monthNameShort} ${toString day} ${time} ${YYYY}";
        };
    in
    {
      lib = {
        fromTimestamp = fromTimestamp;
      };
    };
}
