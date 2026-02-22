-- Add task_result column to cycles for storing automated research results
-- after consensus. Populated by agent-orchestrator when consensus is
-- classified as a research task.

ALTER TABLE cycles ADD COLUMN task_result TEXT;

COMMENT ON COLUMN cycles.task_result IS
  'Research results from automated task execution after consensus. '
  'Populated by agent-orchestrator when consensus is classified as a research task.';
