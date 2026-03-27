//
//  RateLimitMiddleware.swift
//  UnpluggedServer.Middleware
//
//  Created by Sebastian Gonzalez on 3/12/26.
//
// May be unneccesary but should also be only like 20 lines of code

// TODO: Implement RateLimitMiddleware (AsyncMiddleware) — track request counts per userID/IP using in-memory dictionary with timestamps, return 429 Too Many Requests when threshold exceeded, reset counts on time window expiry
