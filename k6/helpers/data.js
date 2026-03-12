import { TEST_PREFIX } from "../config/env.js";

// Deterministic random from VU + iteration for reproducibility
function simpleHash(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32-bit integer
  }
  return Math.abs(hash);
}

const CHAT_TOPICS = [
  "Best approach to reduce carbon emissions",
  "How to improve remote work culture",
  "Priority features for our product roadmap",
  "Most impactful community initiative",
  "Strategy for growing user engagement",
  "Best framework for team decision making",
  "How should we allocate the budget",
  "Top priority for next quarter",
  "Most effective marketing channel",
  "Key metric we should optimize",
];

const PROPOSITION_TEMPLATES = [
  "Focus on {topic} to maximize impact",
  "We should prioritize {topic} above all else",
  "Start with small experiments in {topic}",
  "Build community consensus around {topic}",
  "Invest in research before committing to {topic}",
  "Partner with experts in {topic}",
  "Take an iterative approach to {topic}",
  "Measure everything related to {topic}",
  "Set clear milestones for {topic}",
  "Get stakeholder buy-in for {topic} first",
];

const TOPIC_WORDS = [
  "efficiency", "collaboration", "innovation", "sustainability",
  "transparency", "automation", "community", "engagement",
  "education", "accessibility", "scalability", "reliability",
];

/**
 * Generate a unique chat name for load testing.
 */
export function generateChatName(vuId, iteration) {
  const topicIndex = simpleHash(`${vuId}-${iteration}`) % CHAT_TOPICS.length;
  return `${TEST_PREFIX}chat_${vuId}_${iteration}_${Date.now()}`;
}

/**
 * Generate a proposition text.
 */
export function generateProposition(vuId, iteration) {
  const templateIndex = simpleHash(`prop-${vuId}-${iteration}`) % PROPOSITION_TEMPLATES.length;
  const topicIndex = simpleHash(`topic-${vuId}-${iteration}`) % TOPIC_WORDS.length;
  const template = PROPOSITION_TEMPLATES[templateIndex];
  const topic = TOPIC_WORDS[topicIndex];
  return template.replace("{topic}", topic).substring(0, 200);
}

/**
 * Generate a chat initial message.
 */
export function generateInitialMessage(vuId, iteration) {
  const topicIndex = simpleHash(`msg-${vuId}-${iteration}`) % CHAT_TOPICS.length;
  return CHAT_TOPICS[topicIndex];
}

/**
 * Generate mock ratings for a set of proposition IDs.
 * Returns { "propId": score, ... }
 */
export function generateRatings(propositionIds, vuId) {
  const ratings = {};
  propositionIds.forEach((id, i) => {
    // Score between 20-95, varied by VU
    ratings[String(id)] = 20 + (simpleHash(`rate-${vuId}-${id}-${i}`) % 76);
  });
  return ratings;
}

/**
 * Generate realistic ratings for the mega-chat scenario.
 * Ensures the binary constraint: at least one 0 AND one 100 per submission.
 * Remaining propositions get random scores 1-99.
 *
 * Returns [{ proposition_id, grid_position }, ...]
 */
export function generateRealisticRatings(propositions, vuId) {
  if (!propositions || propositions.length === 0) return [];

  const ratings = [];

  if (propositions.length === 1) {
    // Only one proposition — give it either 0 or 100
    ratings.push({
      proposition_id: propositions[0].id,
      grid_position: simpleHash(`solo-${vuId}-${propositions[0].id}`) % 2 === 0 ? 0 : 100,
    });
    return ratings;
  }

  // Pick indices for the 0 and 100 ratings
  const zeroIdx = simpleHash(`zero-${vuId}-${Date.now()}`) % propositions.length;
  let hundredIdx = simpleHash(`hundred-${vuId}-${Date.now()}`) % propositions.length;
  if (hundredIdx === zeroIdx) {
    hundredIdx = (hundredIdx + 1) % propositions.length;
  }

  for (let i = 0; i < propositions.length; i++) {
    let gridPosition;
    if (i === zeroIdx) {
      gridPosition = 0;
    } else if (i === hundredIdx) {
      gridPosition = 100;
    } else {
      gridPosition = 1 + (simpleHash(`mid-${vuId}-${propositions[i].id}-${i}`) % 99);
    }

    ratings.push({
      proposition_id: propositions[i].id,
      grid_position: gridPosition,
    });
  }

  return ratings;
}
