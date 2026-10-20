"""pip install openai  ->  python examples/openai_example.py"""
import os
from openai import OpenAI

client = OpenAI(base_url=os.getenv("OPENAI_BASE_URL", "http://localhost:8080/v1"),
                api_key=os.getenv("API_KEY", "sk-local"))
MODEL = os.getenv("MODEL", "coder")  # alias of the default model; see client.models.list()

print([m.id for m in client.models.list().data])
r = client.chat.completions.create(model=MODEL, max_tokens=2000,
        messages=[{"role": "user", "content": "Write a quicksort in Python."}])
print(r.choices[0].message.content)

for ev in client.chat.completions.create(model=MODEL, stream=True, max_tokens=500,
        messages=[{"role": "user", "content": "Explain list comprehensions in 2 sentences."}]):
    print(ev.choices[0].delta.content or "", end="", flush=True)
print()
