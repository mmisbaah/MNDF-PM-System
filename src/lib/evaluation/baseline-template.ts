export const RATING_SCALE = Object.freeze({
  1: "Significantly below standard",
  2: "Below standard",
  3: "Meets standard",
  4: "Exceeds standard",
  5: "Significantly exceeds standard",
} as const);

export type PersonnelCategory = "OFFICER" | "NCO" | "PRIVATE" | "CIVILIAN";

export type BaselineCriterion = {
  code: string;
  name: string;
  description: string;
  applicableCategories: readonly PersonnelCategory[];
};

export type BaselineSection = {
  code: string;
  name: string;
  criteria: readonly BaselineCriterion[];
};

const ALL: readonly PersonnelCategory[] = ["OFFICER", "NCO", "PRIVATE", "CIVILIAN"];
const LEADERS: readonly PersonnelCategory[] = ["OFFICER", "NCO", "CIVILIAN"];

export const BASELINE_TEMPLATE = Object.freeze({
  name: "Performance Tracker Pilot Baseline",
  version: 1,
  sections: [
    {
      code: "BASIC_DISCIPLINE",
      name: "Basic discipline",
      criteria: [
        criterion("BD01", "Compliance with lawful orders", "Follows lawful instructions accurately and promptly.", ALL),
        criterion("BD02", "Personal conduct", "Maintains conduct consistent with service expectations.", ALL),
        criterion("BD03", "Dress and bearing", "Maintains appropriate dress, bearing, and personal presentation.", ALL),
        criterion("BD04", "Care of assigned property", "Uses and safeguards assigned property responsibly.", ALL),
      ],
    },
    {
      code: "FOLLOWERSHIP",
      name: "Followership",
      criteria: [
        criterion("FO01", "Reliability", "Completes assigned responsibilities dependably.", ALL),
        criterion("FO02", "Team contribution", "Supports team objectives and colleagues constructively.", ALL),
        criterion("FO03", "Response to direction", "Receives direction and feedback professionally.", ALL),
      ],
    },
    {
      code: "LEADERSHIP",
      name: "Leadership",
      criteria: [
        criterion("LE01", "Direction and clarity", "Provides clear, lawful, and achievable direction.", LEADERS),
        criterion("LE02", "Team development", "Coaches and develops assigned personnel.", LEADERS),
        criterion("LE03", "Responsibility and accountability", "Accepts responsibility for team decisions and outcomes.", LEADERS),
        criterion("LE04", "Fairness in supervision", "Applies standards consistently and without favoritism.", LEADERS),
      ],
    },
    {
      code: "MENTAL_ENDURANCE",
      name: "Mental endurance",
      criteria: [
        criterion("ME01", "Composure under pressure", "Maintains composure during demanding situations.", ALL),
        criterion("ME02", "Persistence", "Sustains appropriate effort when facing difficulty.", ALL),
        criterion("ME03", "Adaptability", "Adjusts constructively to changing requirements.", ALL),
      ],
    },
    {
      code: "PHYSICAL_ENDURANCE",
      name: "Physical endurance",
      criteria: [
        criterion("PE01", "Required fitness standard", "Maintains the fitness standard applicable to the appointment.", ALL),
        criterion("PE02", "Sustained duty readiness", "Maintains physical readiness for assigned duties.", ALL),
        criterion("PE03", "Health and safety discipline", "Applies safe practices during physical duties and training.", ALL),
      ],
    },
    {
      code: "EXAMPLE_TO_OTHERS",
      name: "Example to others",
      criteria: [
        criterion("EX01", "Professional example", "Demonstrates conduct others can appropriately follow.", ALL),
        criterion("EX02", "Integrity", "Acts honestly and accepts responsibility for mistakes.", ALL),
        criterion("EX03", "Respectful behavior", "Treats others with dignity and professional respect.", ALL),
      ],
    },
    {
      code: "RESPECT_FOR_TIME",
      name: "Respect for time",
      criteria: [
        criterion("RT01", "Punctuality", "Reports and responds at required times.", ALL),
        criterion("RT02", "Deadline management", "Completes responsibilities within agreed deadlines.", ALL),
        criterion("RT03", "Time prioritization", "Prioritizes assigned work effectively.", ALL),
      ],
    },
    {
      code: "ATTENDANCE",
      name: "Attendance",
      criteria: [
        criterion("AT01", "Duty attendance", "Maintains attendance consistent with assigned duty requirements.", ALL),
        criterion("AT02", "Absence reporting", "Reports and documents absences through authorized procedures.", ALL),
        criterion("AT03", "Availability for assigned duty", "Remains available as required by the appointment and schedule.", ALL),
      ],
    },
    {
      code: "DECISION_MAKING",
      name: "Decision-making",
      criteria: [
        criterion("DM01", "Assessment of information", "Considers relevant and reliable information before deciding.", LEADERS),
        criterion("DM02", "Timeliness of decisions", "Makes decisions within an appropriate timeframe.", LEADERS),
        criterion("DM03", "Risk and consequence awareness", "Considers foreseeable risks and consequences.", LEADERS),
        criterion("DM04", "Decision accountability", "Explains and accepts responsibility for decisions.", LEADERS),
      ],
    },
    {
      code: "ISLAMIC_DISCIPLINE",
      name: "Islamic discipline",
      criteria: [
        criterion("ID01", "Respect for Islamic values", "Demonstrates respect for the Islamic values governing service conduct.", ALL),
        criterion("ID02", "Ethical conduct", "Applies honesty, fairness, and restraint in professional conduct.", ALL),
        criterion("ID03", "Respect for others", "Demonstrates appropriate respect and consideration toward others.", ALL),
        criterion("ID04", "Personal responsibility", "Takes responsibility for conduct and corrective improvement.", ALL),
      ],
    },
  ] satisfies readonly BaselineSection[],
});

function criterion(
  code: string,
  name: string,
  description: string,
  applicableCategories: readonly PersonnelCategory[],
): BaselineCriterion {
  return { code, name, description, applicableCategories };
}

export const BASELINE_CRITERIA_COUNT = BASELINE_TEMPLATE.sections.reduce(
  (count, section) => count + section.criteria.length,
  0,
);
