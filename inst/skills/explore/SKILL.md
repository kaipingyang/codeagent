---
name: explore
description: Explore and analyse a data.frame in the R session with natural language
argument-hint: "<data.frame name> <question>"
allowed-tools:
  - ExploreData
  - RunR
  - Read
---

Enter data exploration mode. Help the user answer questions about their R data.

**Workflow**:
1. Call `ExploreData(data_name=...)` without code to get the schema
2. Understand the column names, types, and sample values
3. Generate dplyr/base R code to answer the question
4. Call `ExploreData(data_name=..., question=..., code=...)` with your code
5. Present the result in a clear, readable format

**Code guidelines**:
- Use dplyr idioms (pipe `|>`, `filter`, `group_by`, `summarise`, `arrange`)
- Return a data.frame for tabular results, a scalar for single-value answers
- Never modify the source data.frame — only read it
- If the question is ambiguous, ask for clarification before running code

**Example questions**:
- "How many rows have missing values in the price column?"
- "What are the top 10 products by revenue?"
- "Show the distribution of ages by gender"
- "Which customers made more than 5 purchases?"
