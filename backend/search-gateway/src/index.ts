import cors from "cors";
import dotenv from "dotenv";
import express from "express";

dotenv.config();

const port = Number(process.env.PORT ?? 8787);
const apiKey = process.env.TAVILY_API_KEY;
const allowedOrigin = process.env.ALLOWED_ORIGIN ?? "*";

const app = express();

app.use(cors({ origin: allowedOrigin === "*" ? true : allowedOrigin }));
app.use(express.json());

app.get("/health", (_request, response) => {
  response.json({ ok: true, service: "search-gateway" });
});

app.post("/api/search", async (request, response) => {
  const query = String(request.body?.query ?? "").trim();

  if (!query) {
    response.status(400).json({ error: "Query is required." });
    return;
  }

  if (!apiKey) {
    response.status(503).json({
      error: "Missing TAVILY_API_KEY. Copy .env.example to .env and provide a key."
    });
    return;
  }

  const upstreamResponse = await fetch("https://api.tavily.com/search", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      api_key: apiKey,
      query,
      search_depth: "advanced",
      max_results: 5,
      include_answer: true,
      include_raw_content: true
    })
  });

  if (!upstreamResponse.ok) {
    const message = await upstreamResponse.text();
    response.status(502).json({ error: "Upstream search failed.", detail: message });
    return;
  }

  const payload = (await upstreamResponse.json()) as {
    answer?: string;
    results?: Array<{ title?: string; url?: string; content?: string; raw_content?: string }>;
  };

  const citations = (payload.results ?? []).flatMap((item) => {
    if (!item.url || !item.title) {
      return [];
    }

    return [
      {
        title: item.title,
        url: item.url,
        snippet: item.content ?? ""
      }
    ];
  });

  response.json({
    query,
    answer: payload.answer,
    snippets: (payload.results ?? [])
      .map((item) => {
        const body = item.raw_content ?? item.content ?? "";
        const title = item.title?.trim();
        if (!body.trim()) {
          return title ?? "";
        }
        return title ? `${title}: ${body}` : body;
      })
      .filter(Boolean),
    citations
  });
});

app.listen(port, () => {
  console.log(`search-gateway listening on http://localhost:${port}`);
});
