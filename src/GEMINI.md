# Gemini Code Assistant Guide

This document provides guidelines for using the Gemini Code Assistant with this project.

## Project Overview

This project is a real-time strategy base defense game built with the Godot Engine, heavily inspired by the mechanics of Creeper World 3. The core gameplay revolves around building and maintaining a power grid to defend against waves of enemies.

**Core Mechanics:**

*   **Energy Network:** The central nervous system of your base is the energy network. The **Command Center**, the heart of your base, generates energy that is distributed through a network of **Relays**. All buildings must be connected to the Command Center through an unbroken chain of built relays to be powered.
*   **Resource Management:** Energy is the primary resource, but defensive structures like **Cannons** also require **Ammo**. Both resources are transported across the network in the form of packets. Players must balance energy production and consumption to keep their base operational.
*   **Building and Defense:** Players can build various structures:
    *   **Command Center:** The starting point and core of your base.
    *   **Relays:** Extend the reach of your energy network.
    *   **Reactors:** Boost your energy production.
    *   **Cannons:** Automatically defend against enemies, consuming ammo in the process.
*   **Objective:** The goal is to strategically expand your network, manage your resources, and build up your defenses to survive increasingly difficult waves of enemies.

## Getting Started

To run the project, open it in the Godot Engine and press the "Play" button.

## Project Structure

The project is organized into the following directories:

- `src/`: Contains the main source code for the project.
  - `scenes/`: Godot scenes, which represent game objects, levels and managers.
  - `scripts/`: GDScript files, which are not attached to nodes like static classes and templates.
  - `resources/`: Game assets, such as images and sounds.
  - `tilesets/`: Godot tilesets for creating game levels.

## Coding Conventions

- Use GDScript for all game logic.
- Follow the official Godot style guide.
- Use PascalCase for class names.
- Use snake_case for functions and variables.
- Use type hints for all variables and functions.
- Always add clear comments to the code.
- Use clear and descriptive variable names.
- Always explain the changes you are about to make before you start editing the code.

## Influences

This game is highly influenced by Creeper World 3. Many of the systems in this game are inspired by or are direct replications of systems in Creeper World 3. When adding new features, it is likely that they will be very similar to existing features in Creeper World 3.