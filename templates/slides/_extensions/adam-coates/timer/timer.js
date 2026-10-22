// dash array value is the circumference of the circle radius (here 45)
const FULL_DASH_ARRAY = 2 * Math.PI * 45;
// the second limits for color change
const THRESHOLDS = [10, 5];

function initializeTimer(containerId, timeLimit, startOn) {
  let active = true;
  let timePassed = 0;
  let timeLeft = timeLimit;
  let editing = false;
  let wasActive = false;
  let ticking = false;

  document.getElementById(containerId).innerHTML = `
    <div class="base-timer" style="position:relative;">
      <svg id="${containerId}-timer-svg" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
          <circle id="${containerId}-circle" class="base-timer__path-elapsed" cx="50" cy="50" r="45"></circle>
          <path
            id="${containerId}-path-remaining"
            stroke-dasharray="${FULL_DASH_ARRAY}"
            class="base-timer__path-remaining"
            d="M 50 50 m 0 -45 a 45 45 0 0 1 0 90 a 45 45 0 0 1 0 -90">
          </path>
          <text id="${containerId}-label" x="50%" y ="50%" dominant-baseline="middle" text-anchor="middle">
            ${formatTime(timeLeft)}
          </text>
      </svg>
      <div id="${containerId}-edit" style="display:none; position:absolute; top:50%; left:50%; transform:translate(-50%,-50%) scale(3); z-index:10;">
        <input id="${containerId}-input" type="text" value="${formatTime(timeLimit)}"
          style="width:4em; font-size:1.2em; text-align:center; border:2px solid #888; border-radius:4px; padding:2px 4px;"
          placeholder="m:ss">
        <div style="font-size:0.6em; text-align:center; color:#666; margin-top:2px;">m:ss → Enter</div>
      </div>
    </div>
    `;

  const svg = document.getElementById(`${containerId}-timer-svg`);
  const editDiv = document.getElementById(`${containerId}-edit`);
  const input = document.getElementById(`${containerId}-input`);

  // left click: pause / resume
  svg.addEventListener("click", () => {
    if (editing) {
      cancelEdit();
    } else {
      toggleTimer();
    }
  });

  // right click: edit the time (works at any point, even while running)
  svg.addEventListener("contextmenu", (event) => {
    event.preventDefault();
    event.stopPropagation();
    openEdit();
  });

  input.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      applyCustomTime();
    } else if (event.key === "Escape") {
      cancelEdit();
    }
    event.stopPropagation();
  });

  input.addEventListener("click", (event) => {
    event.stopPropagation();
  });

  function parseTimeInput(val) {
    val = val.trim();
    if (val.includes(":")) {
      const parts = val.split(":");
      const m = parseInt(parts[0], 10) || 0;
      const s = parseInt(parts[1], 10) || 0;
      return m * 60 + s;
    }
    return parseInt(val, 10) * 60;
  }

  function openEdit() {
    if (editing) return;
    editing = true;
    wasActive = active;
    if (active) {
      toggleTimer();
    }
    input.value = formatTime(Math.max(timeLeft, 0));
    svg.style.opacity = "0.2";
    editDiv.style.display = "block";
    input.focus();
    input.select();
  }

  function closeEdit() {
    editing = false;
    editDiv.style.display = "none";
    svg.style.opacity = "1";
  }

  function cancelEdit() {
    closeEdit();
    if (wasActive && !active) {
      toggleTimer();
    }
  }

  function applyCustomTime() {
    const totalSeconds = parseTimeInput(input.value);
    if (totalSeconds > 0) {
      timeLimit = totalSeconds;
      timePassed = 0;
      timeLeft = timeLimit;
      document.getElementById(`${containerId}-label`).innerHTML =
        formatTime(timeLeft);
      const path = document.getElementById(`${containerId}-path-remaining`);
      path.classList.remove("lvl0", "lvl1");
      setCircleDasharray();
    }
    closeEdit();
    if (!active) {
      toggleTimer();
    }
    if (!ticking) {
      startTimer();
    }
  }

  if (startOn === "interaction") {
    toggleTimer();
    startOn = "slide";
  }

  function startTimer() {
    ticking = true;
    if (
      active &&
      (startOn === "presentation" || (startOn === "slide" && !isHidden()))
    ) {
      timePassed += 1;
      timeLeft = timeLimit - timePassed;

      document.getElementById(`${containerId}-label`).innerHTML =
        formatTime(timeLeft);

      setCircleDasharray();
      setRemainingPathColor(timeLeft);
    }
    if (timeLeft > 0) {
      setTimeout(startTimer, 1000);
    } else {
      ticking = false;
    }
  }
  startTimer();

  function isHidden() {
    let timecont = document.getElementById(containerId);
    let ancestor = timecont.parentNode;

    while (ancestor.tagName !== "SECTION") {
      ancestor = ancestor.parentNode;
    }
    return ancestor.hidden;
  }

  function toggleTimer() {
    if (active) {
      document.getElementById(`${containerId}-circle`).style.fill = "#fcb";
    } else {
      document.getElementById(`${containerId}-circle`).style.fill = "";
    }
    active = !active;
  }

  function formatTime(time) {
    const minutes = Math.floor(time / 60);
    let seconds = time % 60;

    if (seconds < 10) {
      seconds = `0${seconds}`;
    }

    return `${minutes}:${seconds}`;
  }

  function setRemainingPathColor(timeLeft) {
    const pathId = `${containerId}-path-remaining`;

    for (let i = 0; i < THRESHOLDS.length; i += 1) {
      if (timeLeft < THRESHOLDS[i]) {
        document.getElementById(pathId).classList.remove(`lvl${i - 1}`);
        document.getElementById(pathId).classList.add(`lvl${i}`);
      }
    }
  }

  function setCircleDasharray() {
    let circle_proportions = (timeLeft / timeLimit) * FULL_DASH_ARRAY + " ";
    circle_proportions += (1 - timeLeft / timeLimit) * FULL_DASH_ARRAY;

    document
      .getElementById(`${containerId}-path-remaining`)
      .setAttribute("stroke-dasharray", circle_proportions);
  }
}
