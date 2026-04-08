//
//  routes.swift
//  UnpluggedServer
//
//  Created by Sebastian Gonzalez on 3/12/26.
//

import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: AuthController())
    try app.register(collection: MedalsController())

    let protected = app.grouped(JWTAuthMiddleware())
    try protected.register(collection: UserController())
    try protected.register(collection: SessionController())
    try protected.register(collection: FriendController())
}
