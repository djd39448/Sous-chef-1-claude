// Package openai is a minimal client for the OpenAI API calls the backend
// makes: streaming and JSON-mode chat completions, and image generation.
// Model IDs and parameters are fixed by contract/ai-behavior.md.
package openai

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const (
	chatURL  = "https://api.openai.com/v1/chat/completions"
	imageURL = "https://api.openai.com/v1/images/generations"
)

// Client calls the OpenAI API with a fixed API key.
type Client struct {
	apiKey string
	http   *http.Client
}

// New returns a client authenticated with the given API key.
func New(apiKey string) *Client {
	return &Client{
		apiKey: apiKey,
		http:   &http.Client{Timeout: 3 * time.Minute},
	}
}

// Message is one chat message.
type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// Tool is a function tool offered to the model.
type Tool struct {
	Type     string       `json:"type"`
	Function ToolFunction `json:"function"`
}

// ToolFunction describes a callable function tool.
type ToolFunction struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Parameters  json.RawMessage `json:"parameters"`
}

// ToolCall is a function call the model decided to make.
type ToolCall struct {
	Name      string
	Arguments string
}

// ChatParams configures a chat completion request.
type ChatParams struct {
	Model               string
	Messages            []Message
	Tools               []Tool
	Temperature         *float64
	MaxCompletionTokens *int
}

// StreamResult is the accumulated outcome of a streamed completion.
type StreamResult struct {
	Content   string
	ToolCalls []ToolCall
}

type chatRequest struct {
	Model               string          `json:"model"`
	Messages            []Message       `json:"messages"`
	Tools               []Tool          `json:"tools,omitempty"`
	ToolChoice          string          `json:"tool_choice,omitempty"`
	Stream              bool            `json:"stream"`
	Temperature         *float64        `json:"temperature,omitempty"`
	MaxCompletionTokens *int            `json:"max_completion_tokens,omitempty"`
	ResponseFormat      *responseFormat `json:"response_format,omitempty"`
}

type responseFormat struct {
	Type string `json:"type"`
}

func (c *Client) post(ctx context.Context, url string, body any) (*http.Response, error) {
	buf, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(buf))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")
	return c.http.Do(req)
}

func apiError(resp *http.Response) error {
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 8<<10))
	return fmt.Errorf("openai: %s: %s", resp.Status, strings.TrimSpace(string(body)))
}

// ChatStream runs a streaming chat completion. onDelta is called with each
// text fragment as it arrives. Any tool calls the model makes are accumulated
// and returned in StreamResult; they are not surfaced through onDelta.
func (c *Client) ChatStream(ctx context.Context, p ChatParams, onDelta func(string)) (StreamResult, error) {
	body := chatRequest{
		Model:               p.Model,
		Messages:            p.Messages,
		Tools:               p.Tools,
		Stream:              true,
		Temperature:         p.Temperature,
		MaxCompletionTokens: p.MaxCompletionTokens,
	}
	if len(p.Tools) > 0 {
		body.ToolChoice = "auto"
	}

	resp, err := c.post(ctx, chatURL, body)
	if err != nil {
		return StreamResult{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return StreamResult{}, apiError(resp)
	}

	var content strings.Builder
	type toolAcc struct {
		name string
		args strings.Builder
	}
	tools := map[int]*toolAcc{}
	var order []int

	sc := bufio.NewScanner(resp.Body)
	sc.Buffer(make([]byte, 0, 64<<10), 1<<20)
	for sc.Scan() {
		line := sc.Text()
		if !strings.HasPrefix(line, "data:") {
			continue
		}
		data := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		if data == "" {
			continue
		}
		if data == "[DONE]" {
			break
		}

		var chunk streamChunk
		if err := json.Unmarshal([]byte(data), &chunk); err != nil {
			continue
		}
		if len(chunk.Choices) == 0 {
			continue
		}
		delta := chunk.Choices[0].Delta
		if delta.Content != "" {
			content.WriteString(delta.Content)
			if onDelta != nil {
				onDelta(delta.Content)
			}
		}
		for _, tc := range delta.ToolCalls {
			acc := tools[tc.Index]
			if acc == nil {
				acc = &toolAcc{}
				tools[tc.Index] = acc
				order = append(order, tc.Index)
			}
			if tc.Function.Name != "" {
				acc.name = tc.Function.Name
			}
			acc.args.WriteString(tc.Function.Arguments)
		}
	}
	if err := sc.Err(); err != nil {
		return StreamResult{}, err
	}

	result := StreamResult{Content: content.String()}
	for _, idx := range order {
		acc := tools[idx]
		if acc.name == "" {
			continue
		}
		result.ToolCalls = append(result.ToolCalls, ToolCall{
			Name:      acc.name,
			Arguments: acc.args.String(),
		})
	}
	return result, nil
}

type streamChunk struct {
	Choices []struct {
		Delta struct {
			Content   string `json:"content"`
			ToolCalls []struct {
				Index    int `json:"index"`
				Function struct {
					Name      string `json:"name"`
					Arguments string `json:"arguments"`
				} `json:"function"`
			} `json:"tool_calls"`
		} `json:"delta"`
	} `json:"choices"`
}

// ChatJSON runs a non-streaming chat completion in JSON-object response mode
// and returns the model's message content.
func (c *Client) ChatJSON(ctx context.Context, p ChatParams) (string, error) {
	body := chatRequest{
		Model:               p.Model,
		Messages:            p.Messages,
		Stream:              false,
		Temperature:         p.Temperature,
		MaxCompletionTokens: p.MaxCompletionTokens,
		ResponseFormat:      &responseFormat{Type: "json_object"},
	}

	resp, err := c.post(ctx, chatURL, body)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", apiError(resp)
	}

	var parsed struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return "", err
	}
	if len(parsed.Choices) == 0 {
		return "", fmt.Errorf("openai: empty response")
	}
	return parsed.Choices[0].Message.Content, nil
}

// GenerateImage creates one 1024x1024 image with gpt-image-1 and returns it
// base64-encoded (PNG).
func (c *Client) GenerateImage(ctx context.Context, prompt string) (string, error) {
	body := map[string]any{
		"model":  "gpt-image-1",
		"prompt": prompt,
		"n":      1,
		"size":   "1024x1024",
	}

	resp, err := c.post(ctx, imageURL, body)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", apiError(resp)
	}

	var parsed struct {
		Data []struct {
			B64JSON string `json:"b64_json"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return "", err
	}
	if len(parsed.Data) == 0 || parsed.Data[0].B64JSON == "" {
		return "", fmt.Errorf("openai: no image returned")
	}
	return parsed.Data[0].B64JSON, nil
}
